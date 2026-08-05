# Multi-OS LPAR Support (IBM i / AIX / Linux) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Broaden LPAR discovery in `bluexscrt_config_api.sh`/`bluexport_api.sh` from IBM i-only to all PowerVS OS types (ibmi/aix/linux/other), and gate the IBM i-only `CHGASPACT` ASP-flush (currently unconditional before snapshot create, volume clone execute, and image/cloud-storage capture) so it only runs when the target LPAR's OS is `ibmi`.

**Architecture:** `.systems[]` in the bluexscrt JSON gains `os` (normalized category) and `osDetail` (raw API value) fields, populated during discovery (`-updlpars`) and by a new required `-addlpar` argument. `bluexport_api.sh` resolves `vsi_os` once per run (in `check_locally_VSI_exists`) and uses it to skip the IBM i-only SSH/CL portions of `get_iASP_name` and the three `flush_asps` call sites for non-`ibmi` targets, while every other operation (GRS, tiers, VSI start/oper/task/srcmon, buckets) stays untouched.

**Tech Stack:** Bash (IBM i PASE-compatible), `jq`, `curl`, `ssh`. No new external dependencies.

## Global Constraints

- Both scripts must remain IBM i PASE/QShell-compatible (shebang `#!/bin/bash`, PASE ships bash) — no Linux-only constructs (`readarray`, `/proc`, GNU-only flags not already used elsewhere in these files).
- Any script-version flag change requires a semantic version bump per project convention, applied automatically (never ask): `bluexscrt_config_api.sh` gets a **MAJOR** bump (`1.6` → `2.0`, the `-addlpar` argument change is breaking); `bluexport_api.sh` gets a **MINOR** bump (`1.12.1` → `1.13.0`, purely additive for existing IBM i-only installs).
- `bluexport_api.sh` never writes to the bluexscrt JSON's `.systems[]` — that boundary is preserved; only `bluexscrt_config_api.sh` writes it.
- Unknown/unrecognized `osType` values must classify as `other`, never assumed `linux` by elimination.
- `vsi_os` must be initialized empty and only assigned (with the `// "ibmi"` legacy fallback) after `check_locally_VSI_exists` has confirmed a matching `.systems[]` entry exists — never set speculatively before that.
- Cross-workspace name-collision disambiguation (merging `check_locally_VSI_exists`/`vsi_id_bluexscrt`, ambiguous-match detection, workspace-scoped discovery matching) is explicitly out of scope for this plan — deferred by the user to a future iteration.
- Spec: `docs/superpowers/specs/2026-08-05-multi-os-lpar-support-design.md` (approved, read before starting if you need the full rationale).

---

## File Structure

- Modify `bluexscrt_config_api.sh`: OS classification in `run_updlpars_api` (~line 950), `-addlpar` case block (~line 1461) and its `usage()` entry (~line 68), `create_vsi_user_from_json` (~line 551), `VERSION` (line 10).
- Modify `bluexport_api.sh`: `check_locally_VSI_exists` (line 1374) and `get_iASP_name` (line 1273), the three `flush_asps` call sites (`do_snap_create` line 1449, `do_volume_clone_execute` line 1729, capture flow line 6260-6279), `Version` (line 143).
- Modify `README.md`: `-updlpars`/`-addlpar` sections, note on CHGASPACT scope.
- Modify `CHANGELOG.md`: entries for both version bumps.

---

### Task 1: OS classification in discovery (`run_updlpars_api`)

**Files:**
- Modify: `bluexscrt_config_api.sh:950-1201` (function `run_updlpars_api`)

**Interfaces:**
- Produces: every entry written to `.systems[]` now has `os` (`"ibmi"|"aix"|"linux"|"other"`, always present, never blank) and `osDetail` (raw string, always present) fields. This is what Task 2, 3, 4, 5 read.

- [ ] **Step 1: Write and run a standalone verification script for the classification logic**

Create `/tmp/test_os_classify.sh`:

```bash
#!/bin/bash
set -euo pipefail

classify_os() {
	jq -r '
		def is_ibmi:
			((.osType? // "" | ascii_downcase) == "ibmi")
			or ((.operatingSystem? | type == "string") and ((.operatingSystem | ascii_downcase) | test("ibmi|v7r[0-9]m[0-9]"; "i")))
			or ((.operatingSystem.type? // "" | ascii_downcase) == "ibmi")
			or (.configuration.softwareLicenses.ibmiCSS? == true)
			or (.softwareLicenses.ibmiCSS? == true);
		def linux_distros: ["rhel","sles","suse","ubuntu","debian","centos","fedora","rocky","almalinux","oraclelinux"];
		if is_ibmi then "ibmi"
		elif ((.osType? // "" | ascii_downcase) == "aix") then "aix"
		elif ((.osType? // "" | ascii_downcase) as $t | linux_distros | index($t) != null) then "linux"
		else "other"
		end
	' <<<"$1"
}

os_detail() {
	jq -r '
		if ((.operatingSystem? // "" | ascii_downcase) == "unknown" or (.operatingSystem? // "") == "") then
			(.osType? // "unknown")
		else
			.operatingSystem
		end
	' <<<"$1"
}

check() {
	local label="$1" json="$2" expect_os="$3" expect_detail="$4"
	local got_os got_detail
	got_os=$(classify_os "$json")
	got_detail=$(os_detail "$json")
	if [[ "$got_os" == "$expect_os" && "$got_detail" == "$expect_detail" ]]; then
		echo "PASS: $label -> os=$got_os detail=$got_detail"
	else
		echo "FAIL: $label -> got os=$got_os detail=$got_detail, expected os=$expect_os detail=$expect_detail"
		exit 1
	fi
}

# Real payloads pulled live from the user's PowerVS account, 2026-08-05
check "IBM i (IBMiCC)" '{"serverName":"IBMiCC","osType":"ibmi","operatingSystem":"V7R6M0 450 2"}' "ibmi" "V7R6M0 450 2"
check "AIX" '{"serverName":"AIX","osType":"aix","operatingSystem":"Unknown"}' "aix" "aix"
check "RHEL (PAO)" '{"serverName":"PAO","osType":"rhel","operatingSystem":"Unknown"}' "linux" "rhel"
check "RHEL (nfs, full banner)" '{"serverName":"nfs","osType":"rhel","operatingSystem":"Linux/Red Hat Enterprise Linux 6.12.0-55.50.1.el10_0.ppc10.0 (Coughlan), 10.0 (Coughlan)"}' "linux" "Linux/Red Hat Enterprise Linux 6.12.0-55.50.1.el10_0.ppc10.0 (Coughlan), 10.0 (Coughlan)"
check "Unknown osType (must be other, not linux)" '{"serverName":"weird","osType":"solaris","operatingSystem":"Unknown"}' "other" "solaris"
check "No signal at all" '{"serverName":"noinfo"}' "other" "unknown"
check "Legacy softwareLicenses.ibmiCSS schema" '{"serverName":"old","softwareLicenses":{"ibmiCSS":true}}' "ibmi" "unknown"

echo "ALL PASS"
```

Run: `bash /tmp/test_os_classify.sh`
Expected: 7 `PASS:` lines followed by `ALL PASS`. If any `FAIL:` line appears, fix the jq filters above before continuing (do not proceed to Step 2 with a failing classifier).

- [ ] **Step 2: Clean up the verification script**

Run: `rm -f /tmp/test_os_classify.sh`

- [ ] **Step 3: Replace the classification block in `run_updlpars_api`**

Read `bluexscrt_config_api.sh` around line 950-1201 first to confirm current line numbers (this file has been edited multiple times this session and line numbers drift).

Replace the whole function body from `run_updlpars_api() {` to its closing `}` (currently `bluexscrt_config_api.sh:950-1202`) with:

```bash
run_updlpars_api() {
	get_iam_token
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - === Starting -updlpars using IBM Cloud APIs ===" "1"

	# 0) Refresh cos_instances from IBM Cloud (Cloud Object Storage instances)
	cos_raw=$(cos_ins_ls 2>>"$log_file")
	cos_total=$(jq '[.resources[]?] | length' <<<"$cos_raw" 2>/dev/null)
	cos_instances_json=$(jq '
		[.resources[]?
			| select(.crn | contains(":cloud-object-storage:"))
			| {name, guid, crn}]
		| reduce .[] as $i ({}; .[$i.name] = {guid: $i.guid, crn: $i.crn})
	' <<<"$cos_raw")

	if [[ -n "$cos_instances_json" && "$cos_instances_json" != "{}" ]]; then
		tmp_cos="${CONFIG_JSON}.tmp"
		jq --argjson cos "$cos_instances_json" '.cos_instances = $cos' "$CONFIG_JSON" > "$tmp_cos" && mv "$tmp_cos" "$CONFIG_JSON"
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - cos_instances section refreshed from IBM Cloud ($(jq 'length' <<<"$cos_instances_json") instance(s))." "1"
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No Cloud Object Storage instances found among ${cos_total:-0} resource instance(s) scanned; cos_instances not updated." "1"
	fi

	# Load current systems[] from JSON (to detect existing vs new)
	# Aqui guardamos APENAS o array .systems
	existing_systems_json=$(jq '.systems // []' "$CONFIG_JSON")

	all_systems=""

	# Lista de workspaces definidos no JSON
	mapfile -t ws_keys < <(jq -r '.workspaces | keys[]' "$CONFIG_JSON")

	for ws in "${ws_keys[@]}"; do
		# Preparar contexto para este workspace (base_url, CLOUD_INSTANCE_ID, CRN)
		if ! set_ws_context "$ws"; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Skipping workspace '$ws' (no valid context)" "1"
			continue
		fi

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Processing workspace '$ws'..." "1"

		# Chama o API de lista de instâncias
		resp=$(ins_ls 2>>"$log_file")

		# Se resposta vazia, ignora logo
		if [[ -z "$resp" || "$resp" == "null" ]]; then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Empty response from ins_ls in '$ws' (skipping)" "1"
			continue
		fi

		local ws_found=0
		local ws_new_count=0
		local ws_existing_count=0

		# Iterar sobre TODAS as pvmInstances de todos os OS (ibmi/aix/linux/other)
		while IFS= read -r inst; do
			ws_found=1

			# Classificar o OS: ibmi (deteção multi-sinal já existente) / aix / linux (distros
			# conhecidas) / other (qualquer osType não reconhecido - nunca assumir linux por
			# eliminação, ver spec 2026-08-05 secção A).
			os_class=$(jq -r '
				def is_ibmi:
					((.osType? // "" | ascii_downcase) == "ibmi")
					or ((.operatingSystem? | type == "string") and ((.operatingSystem | ascii_downcase) | test("ibmi|v7r[0-9]m[0-9]"; "i")))
					or ((.operatingSystem.type? // "" | ascii_downcase) == "ibmi")
					or (.configuration.softwareLicenses.ibmiCSS? == true)
					or (.softwareLicenses.ibmiCSS? == true);
				def linux_distros: ["rhel","sles","suse","ubuntu","debian","centos","fedora","rocky","almalinux","oraclelinux"];
				if is_ibmi then "ibmi"
				elif ((.osType? // "" | ascii_downcase) == "aix") then "aix"
				elif ((.osType? // "" | ascii_downcase) as $t | linux_distros | index($t) != null) then "linux"
				else "other"
				end
			' <<<"$inst")

			os_detail=$(jq -r '
				if ((.operatingSystem? // "" | ascii_downcase) == "unknown" or (.operatingSystem? // "") == "") then
					(.osType? // "unknown")
				else
					.operatingSystem
				end
			' <<<"$inst")

			# Nome e ID: suportar tanto serverName/pvmInstanceID como name/id
			name=$(jq -r '.serverName // .name // "UNKNOWN"' <<<"$inst")
			pvmid=$(jq -r '.pvmInstanceID // .id // ""'      <<<"$inst")

			if [[ -z "$pvmid" || "$pvmid" == "null" ]]; then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Skipping LPAR '$name' in '$ws' (no pvmInstanceID/id)." "1"
				continue
			fi

			# Verificar se este nome já existe em .systems (case-insensitive)
			existing_obj=$(jq -r --arg name_lc "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" '
				.[]? | select((.name // "" | ascii_downcase) == $name_lc)
			' <<<"$existing_systems_json")

			if [[ -n "$existing_obj" && "$existing_obj" != "null" ]]; then
				# Já existe: mantemos o IP anterior, actualizamos ws/pvmid/os/osDetail
				old_ip=$(jq -r '.ip // ""' <<<"$existing_obj")
				ws_existing_count=$((ws_existing_count + 1))

				system_obj=$(jq -n \
					--arg name "$name" \
					--arg ip "$old_ip" \
					--arg pvmid "$pvmid" \
					--arg ws "$ws" \
					--arg os "$os_class" \
					--arg osdetail "$os_detail" \
					'{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws, os:$os, osDetail:$osdetail}')

			else
				ws_new_count=$((ws_new_count + 1))
				# LPAR novo: decidir IP (com escolha se houver mais do que um)
				# Suportar:
				#  - addresses[].ipAddress/ip
				#  - networks[].ipAddress/ip/ipAddresses[]
				#  - networkPorts[].privateIP/ipAddress
				mapfile -t ip_array < <(jq -r '
					[
						(.addresses[]?      | .ipAddress?),
						(.addresses[]?      | .ip?),
						(.networks[]?       | .ipAddress?),
						(.networks[]?       | .ip?),
						(.networks[]?       | .ipAddresses[]?),
						(.networkPorts[]?   | .privateIP?),
						(.networkPorts[]?   | .ipAddress?)
					]
					| map(select(. != null))
					| unique[]
				' <<<"$inst")

				chosen_ip=""
				ip_count=${#ip_array[@]}

				if (( ip_count == 0 )); then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' has no IP addresses reported by API (storing empty IP)." "1"

				elif (( ip_count == 1 )); then
					chosen_ip="${ip_array[0]}"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - New LPAR '$name' in workspace '$ws' -> single IP detected: $chosen_ip" "1"

				else
					echoscreen "" "1"
					echoscreen "============================================================" "1"
					echoscreen "LPAR '$name' in workspace '$ws' has multiple IP addresses:" "1"
					for (( idx=0; idx<ip_count; idx++ )); do
						echoscreen "  [$((idx+1))] ${ip_array[$idx]}" "1"
					done
					echoscreen "------------------------------------------------------------" "1"

					# Tentar sugerir IP com base em prefNetwork/prefIP
					default_choice=""
					if [[ -n "${prefNetwork:-}" ]]; then
						for (( idx=0; idx<ip_count; idx++ )); do
							if [[ "${ip_array[$idx]}" == "$prefNetwork"* ]]; then
								default_choice=$((idx+1))
								break
							fi
						done
					fi

					if [[ -z "$default_choice" && -n "${prefIP:-}" ]]; then
						for (( idx=0; idx<ip_count; idx++ )); do
							if [[ "${ip_array[$idx]}" == "$prefIP" ]]; then
								default_choice=$((idx+1))
								break
							fi
						done
					fi

					if [[ -n "$default_choice" ]]; then
						echoscreen "Suggested default based on preferences (prefNetwork/prefIP): [$default_choice]" "1"
					fi

					while true; do
						# Prompt vai sempre para o terminal real
						printf "Select IP index [1-%d] (ENTER for default %s): " \
							"$ip_count" "${default_choice:-1}" > /dev/tty

						# Ler SEMPRE do /dev/tty, nunca do stdin do while < <(...)
						if ! read -r choice < /dev/tty; then
							# Se por algum motivo não houver input (EOF, etc.) assumimos default
							choice="${default_choice:-1}"
						fi

						# Se o utilizador só carregar ENTER:
						if [[ -z "$choice" ]]; then
							if [[ -n "$default_choice" ]]; then
								choice="$default_choice"
							else
								# Sem default configurado → assume índice 1
								choice=1
							fi
						fi

						# Validar se é numérico
						if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
							echo "Invalid input. Please enter a number between 1 and $ip_count, or press ENTER for default." > /dev/tty
							continue
						fi

						# Validar range
						if (( choice < 1 || choice > ip_count )); then
							echo "Choice out of range. Please select between 1 and $ip_count." > /dev/tty
							continue
						fi

						break
					done

					chosen_ip="${ip_array[$((choice-1))]}"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Selected IP '$chosen_ip' for LPAR '$name'." "1"
				fi

				system_obj=$(jq -n \
					--arg name "$name" \
					--arg ip "$chosen_ip" \
					--arg pvmid "$pvmid" \
					--arg ws "$ws" \
					--arg os "$os_class" \
					--arg osdetail "$os_detail" \
					'{name:$name, ip:$ip, pvmInstanceID:$pvmid, workspace:$ws, os:$os, osDetail:$osdetail}')
			fi

			# Acrescenta este objecto JSON (numa linha) ao acumulador
			all_systems+="$system_obj"$'\n'

		done < <(printf '%s\n' "$resp" | jq -c '.pvmInstances[]?')

		if (( ws_found == 0 )); then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> No LPARs found in '$ws'." "1"
		elif (( ws_new_count > 0 )); then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$ws': $ws_new_count new LPAR(s) added, $ws_existing_count confirmed unchanged." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -> Workspace '$ws': $ws_existing_count LPAR(s) confirmed, no changes." "1"
		fi
	done

	# Se não conseguimos nada do API, não mexemos no JSON
	if [[ -z "$all_systems" ]]; then
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - WARNING: No LPARs retrieved from any workspace; keeping existing systems[] as-is." "1"
	else
		# Converte as linhas em array JSON e sobrescreve systems[]
		systems_json=$(printf '%s\n' "$all_systems" | jq -s '.')
		tmp_file="${CONFIG_JSON}.tmp"
		jq --argjson systems "$systems_json" '.systems = $systems' "$CONFIG_JSON" > "$tmp_file" && \
			mv "$tmp_file" "$CONFIG_JSON"

		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Systems updated from IBM Cloud (all OS: new LPARs added, obsolete removed)." "1"
	fi

	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Final (masked) config snapshot:" "1"
	print_masked_config
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - -updlpars finished." "1"
}
```

- [ ] **Step 4: Syntax check**

Run: `bash -n bluexscrt_config_api.sh`
Expected: no output (clean exit).

- [ ] **Step 5: Update `usage()` text for `-updlpars`**

In `bluexscrt_config_api.sh`, find the `-updlpars` block inside `usage()` (currently around line 75-80):

Old:
```
  -updlpars
      Refresh IBM i LPARs and COS instances from IBM Cloud APIs:
        - discover IBM i LPARs in all configured workspaces
        - add new IBM i systems to .systems[], remove obsolete ones, refresh pvmInstanceID
        - refresh .cos_instances from IBM Cloud
      At the end, prints a masked snapshot of the current JSON config.
```

New:
```
  -updlpars
      Refresh LPARs (all OS: ibmi/aix/linux/other) and COS instances from IBM Cloud APIs:
        - discover all LPARs in all configured workspaces, classifying each as
          os=ibmi|aix|linux|other (osDetail keeps the raw API value)
        - add new systems to .systems[], remove obsolete ones, refresh pvmInstanceID/os/osDetail
        - refresh .cos_instances from IBM Cloud
      At the end, prints a masked snapshot of the current JSON config.
      Upgrade note: run this once after upgrading to backfill os/osDetail on any
      pre-existing .systems[] entry that predates this field (treated as ibmi until then).
```

- [ ] **Step 6: Manually verify the diff**

Run: `git diff bluexscrt_config_api.sh`
Expected: only the `run_updlpars_api` function body and the `-updlpars` usage text changed; no unrelated lines touched.

- [ ] **Step 7: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexscrt_config_api.sh
git commit -m "$(cat <<'EOF'
run_updlpars_api: discover all OS (ibmi/aix/linux/other), not just IBM i

Adds os/osDetail fields to every .systems[] entry, classifying via
osType (aix/known Linux distro codenames) with the existing multi-signal
IBM i detection unchanged. Unrecognized osType values fall back to
"other", never assumed "linux" by elimination.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `-addlpar` required `OS` argument

**Files:**
- Modify: `bluexscrt_config_api.sh:1461-1500` (`-addlpar` case block)
- Modify: `bluexscrt_config_api.sh:68-73` (`usage()` entry)

**Interfaces:**
- Consumes: nothing from Task 1 (independent code path), but writes the same `os`/`osDetail` shape Task 1 produces.
- Produces: `-addlpar NAME IP PVM_ID WORKSPACE_SHORT OS` — manually-added entries carry `os` (validated, lowercased) and `osDetail:""`.

- [ ] **Step 1: Read current `-addlpar` block to confirm line numbers**

Run: `grep -n '\-addlpar)' bluexscrt_config_api.sh`

- [ ] **Step 2: Replace the `-addlpar` case block**

Replace:
```bash
  -addlpar)
    # Now: NAME IP PVM_ID WORKSPACE_SHORT  (no LPAR label)
    if [[ $# -ne 5 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT" >&2
      exit 1
    fi

    # ensure_config_exists  # se quiseres obrigar a escolher o JSON aqui também

    lpar_name="$2"
    lpar_ip="$3"
    lpar_pvmid="$4"
    lpar_ws="$5"

    # Upsert system entry (case-insensitive on .name), sem campo "lpar"
    jq_inplace '
      .systems |= (
        ( . // [] )
        | map(select((.name // "" | ascii_downcase) != ($name | ascii_downcase)))
        + [ {
              "name": $name,
              "ip": $ip,
              "pvmInstanceID": $pvmid,
              "workspace": $ws
            } ]
      )
    ' \
      --arg name  "$lpar_name" \
      --arg ip    "$lpar_ip" \
      --arg pvmid "$lpar_pvmid" \
      --arg ws    "$lpar_ws"

    echo ""
    echo "LPAR '$lpar_name' added/updated in $CONFIG_JSON:"
    jq -r '
      .systems[]
      | select((.name // "" | ascii_downcase) == ($n | ascii_downcase))
    ' --arg n "$lpar_name" "$CONFIG_JSON"
    ;;
```

With:
```bash
  -addlpar)
    # Now: NAME IP PVM_ID WORKSPACE_SHORT OS
    if [[ $# -ne 6 ]]; then
      echo "ERROR: Wrong syntax." >&2
      echo "Usage: $(basename "$0") -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS" >&2
      echo "  OS must be one of: ibmi | aix | linux | other" >&2
      exit 1
    fi

    # ensure_config_exists  # se quiseres obrigar a escolher o JSON aqui também

    lpar_name="$2"
    lpar_ip="$3"
    lpar_pvmid="$4"
    lpar_ws="$5"
    lpar_os=$(printf '%s' "$6" | tr '[:upper:]' '[:lower:]')

    case "$lpar_os" in
      ibmi|aix|linux|other)
        ;;
      *)
        echo "ERROR: Invalid OS '$6'. Must be one of: ibmi | aix | linux | other" >&2
        exit 1
        ;;
    esac

    # Upsert system entry (case-insensitive on .name), sem campo "lpar"
    jq_inplace '
      .systems |= (
        ( . // [] )
        | map(select((.name // "" | ascii_downcase) != ($name | ascii_downcase)))
        + [ {
              "name": $name,
              "ip": $ip,
              "pvmInstanceID": $pvmid,
              "workspace": $ws,
              "os": $os,
              "osDetail": ""
            } ]
      )
    ' \
      --arg name  "$lpar_name" \
      --arg ip    "$lpar_ip" \
      --arg pvmid "$lpar_pvmid" \
      --arg ws    "$lpar_ws" \
      --arg os    "$lpar_os"

    echo ""
    echo "LPAR '$lpar_name' added/updated in $CONFIG_JSON:"
    jq -r '
      .systems[]
      | select((.name // "" | ascii_downcase) == ($n | ascii_downcase))
    ' --arg n "$lpar_name" "$CONFIG_JSON"
    ;;
```

- [ ] **Step 3: Update `usage()` entry for `-addlpar`**

Replace:
```
  -addlpar NAME IP PVM_ID WORKSPACE_SHORT
      Add or update a single LPAR (system) entry in .systems[]:
        NAME            Logical system name (e.g. ibmi75m2)
        IP              IP address used for SSH and bluexport operations
        PVM_ID          PowerVS pvmInstanceID of the LPAR
        WORKSPACE_SHORT Workspace key as defined under .workspaces in the JSON (e.g. WSMAD2)
```

With:
```
  -addlpar NAME IP PVM_ID WORKSPACE_SHORT OS
      Add or update a single LPAR (system) entry in .systems[]:
        NAME            Logical system name (e.g. ibmi75m2)
        IP              IP address used for SSH and bluexport operations
        PVM_ID          PowerVS pvmInstanceID of the LPAR
        WORKSPACE_SHORT Workspace key as defined under .workspaces in the JSON (e.g. WSMAD2)
        OS              ibmi | aix | linux | other - determines whether operations that
                         flush ASPs (CHGASPACT) run for this LPAR (ibmi only)
```

Also update the example line further down in `usage()`:

Replace:
```
  $(basename "$0") -addlpar ibmi75m2 172.26.2.5 7ed4ea03-... WSMAD2
```

With:
```
  $(basename "$0") -addlpar ibmi75m2 172.26.2.5 7ed4ea03-... WSMAD2 ibmi
```

- [ ] **Step 4: Syntax check**

Run: `bash -n bluexscrt_config_api.sh`
Expected: no output.

- [ ] **Step 5: Write and run a functional test against a scratch JSON**

Create `/tmp/test_addlpar.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO=/home/rqmartins/Git/bluexport_api
export HOME="$WORKDIR"
mkdir -p "$WORKDIR"

CONF="$WORKDIR/bluexport_api_conf.json"
JSON="$WORKDIR/bluexscrt_test.json"

cat > "$CONF" <<EOF
{"bluexscrt": "$JSON", "log_file": "$WORKDIR/test.log"}
EOF

cat > "$JSON" <<'EOF'
{"apikey":"x","workspaces":{},"systems":[]}
EOF

fail=0

echo "=== Case 1: wrong arg count (5 args, old syntax) - must fail ==="
if "$REPO/bluexscrt_config_api.sh" -addlpar name1 10.0.0.1 pvm1 WS1 2>&1 | grep -q "Wrong syntax"; then
	echo "PASS: rejected old 5-arg syntax"
else
	echo "FAIL: did not reject old 5-arg syntax"
	fail=1
fi

echo "=== Case 2: invalid OS value - must fail ==="
if "$REPO/bluexscrt_config_api.sh" -addlpar name1 10.0.0.1 pvm1 WS1 solaris 2>&1 | grep -q "Invalid OS"; then
	echo "PASS: rejected invalid OS value"
else
	echo "FAIL: did not reject invalid OS value"
	fail=1
fi

echo "=== Case 3: valid add (ibmi) ==="
"$REPO/bluexscrt_config_api.sh" -addlpar testibmi 10.0.0.1 pvm1 WS1 ibmi >/dev/null 2>&1
got=$(jq -r '.systems[] | select(.name=="testibmi") | .os' "$JSON")
if [[ "$got" == "ibmi" ]]; then
	echo "PASS: os=ibmi stored correctly"
else
	echo "FAIL: expected os=ibmi, got '$got'"
	fail=1
fi

echo "=== Case 4: valid add (AIX, uppercase input normalized to lowercase) ==="
"$REPO/bluexscrt_config_api.sh" -addlpar testaix 10.0.0.2 pvm2 WS1 AIX >/dev/null 2>&1
got=$(jq -r '.systems[] | select(.name=="testaix") | .os' "$JSON")
if [[ "$got" == "aix" ]]; then
	echo "PASS: OS input normalized to lowercase aix"
else
	echo "FAIL: expected os=aix, got '$got'"
	fail=1
fi

echo "=== Case 5: osDetail is empty string for manual add ==="
got=$(jq -r '.systems[] | select(.name=="testaix") | .osDetail' "$JSON")
if [[ "$got" == "" ]]; then
	echo "PASS: osDetail empty for manual add"
else
	echo "FAIL: expected empty osDetail, got '$got'"
	fail=1
fi

if [[ $fail -eq 0 ]]; then
	echo "ALL PASS"
else
	echo "SOME TESTS FAILED"
	exit 1
fi
```

Run: `bash /tmp/test_addlpar.sh`
Expected: 5 `PASS:` lines followed by `ALL PASS`.

Note: the script uses `set -euo pipefail` and calls `ensure_config_exists`-style logic is commented out, but other parts of the real script may prompt interactively — if this test hangs waiting for input, check whether `-addlpar` in the current codebase calls anything interactive before the case block (it shouldn't; `-addlpar` doesn't call `ensure_config_exists`). If it hangs, redirect stdin from `/dev/null` in the test invocations instead of debugging blind.

- [ ] **Step 6: Clean up the verification script**

Run: `rm -f /tmp/test_addlpar.sh`

- [ ] **Step 7: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexscrt_config_api.sh
git commit -m "$(cat <<'EOF'
-addlpar: require explicit OS argument (ibmi|aix|linux|other)

Breaking change: old 4-argument invocations now fail with a clear
syntax error instead of silently assuming ibmi. osDetail is left
empty for manually-added entries (only auto-discovery populates it).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Filter `create_vsi_user_from_json` to `os == ibmi`

**Files:**
- Modify: `bluexscrt_config_api.sh:551-580` (function `create_vsi_user_from_json`)

**Interfaces:**
- Consumes: `.systems[].os` (produced by Task 1/2). Missing field (pre-upgrade entries not yet refreshed) treated as `ibmi`.

- [ ] **Step 1: Read current line numbers**

Run: `grep -n 'mapfile -t systems' bluexscrt_config_api.sh`

- [ ] **Step 2: Replace the systems-loading block**

Replace:
```bash
  mapfile -t systems < <(jq -c '.systems[]?' "$CONFIG_JSON")
  if (( ${#systems[@]} == 0 )); then
    echo "### No systems[] defined in $CONFIG_JSON; nothing to do." | tee -a "$log_file"
    return 0
  fi
```

With:
```bash
  local skipped_non_ibmi
  skipped_non_ibmi=$(jq '[.systems[]? | select((.os // "ibmi") != "ibmi")] | length' "$CONFIG_JSON")
  if (( skipped_non_ibmi > 0 )); then
    echo "### Skipping $skipped_non_ibmi non-IBM i system(s) in .systems[] (SSH user setup is IBM i-only for now)." | tee -a "$log_file"
  fi

  mapfile -t systems < <(jq -c '.systems[]? | select((.os // "ibmi") == "ibmi")' "$CONFIG_JSON")
  if (( ${#systems[@]} == 0 )); then
    echo "### No IBM i systems[] defined in $CONFIG_JSON; nothing to do." | tee -a "$log_file"
    return 0
  fi
```

- [ ] **Step 3: Syntax check**

Run: `bash -n bluexscrt_config_api.sh`
Expected: no output.

- [ ] **Step 4: Write and run a functional test**

Create `/tmp/test_create_vsi_user_filter.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CONFIG_JSON="$WORKDIR/test.json"
log_file="$WORKDIR/test.log"
: > "$log_file"

cat > "$CONFIG_JSON" <<'EOF'
{
  "systems": [
    {"name":"ibmi1","os":"ibmi"},
    {"name":"aix1","os":"aix"},
    {"name":"linux1","os":"linux"},
    {"name":"legacy1"}
  ]
}
EOF

skipped_non_ibmi=$(jq '[.systems[]? | select((.os // "ibmi") != "ibmi")] | length' "$CONFIG_JSON")
mapfile -t systems < <(jq -c '.systems[]? | select((.os // "ibmi") == "ibmi")' "$CONFIG_JSON")

fail=0

if [[ "$skipped_non_ibmi" == "2" ]]; then
	echo "PASS: skipped_non_ibmi=2 (aix1, linux1)"
else
	echo "FAIL: expected skipped_non_ibmi=2, got $skipped_non_ibmi"
	fail=1
fi

if (( ${#systems[@]} == 2 )); then
	echo "PASS: 2 systems selected (ibmi1, legacy1)"
else
	echo "FAIL: expected 2 systems selected, got ${#systems[@]}"
	fail=1
fi

names=$(printf '%s\n' "${systems[@]}" | jq -r '.name' | sort | tr '\n' ',')
if [[ "$names" == "ibmi1,legacy1," ]]; then
	echo "PASS: correct names selected (ibmi1, legacy1 - legacy1 has no os field, falls back to ibmi)"
else
	echo "FAIL: expected 'ibmi1,legacy1,', got '$names'"
	fail=1
fi

if [[ $fail -eq 0 ]]; then
	echo "ALL PASS"
else
	echo "SOME TESTS FAILED"
	exit 1
fi
```

Run: `bash /tmp/test_create_vsi_user_filter.sh`
Expected: 3 `PASS:` lines followed by `ALL PASS`.

- [ ] **Step 5: Clean up the verification script**

Run: `rm -f /tmp/test_create_vsi_user_filter.sh`

- [ ] **Step 6: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexscrt_config_api.sh
git commit -m "$(cat <<'EOF'
create_vsi_user_from_json: skip non-IBM i systems

SSH user provisioning (DSPUSRPRF/CRTUSRPRF) is IBM i-only CL; now that
.systems[] can contain AIX/Linux entries, filter to os==ibmi (missing
os field, i.e. pre-upgrade entries, still defaults to ibmi) and report
how many non-IBM i entries were skipped.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `vsi_os` resolution and IBM i-only iASP discovery gate

**Files:**
- Modify: `bluexport_api.sh:1273-1400` (functions `get_iASP_name` and `check_locally_VSI_exists`)

**Interfaces:**
- Consumes: `.systems[].os` from the bluexscrt JSON (produced by Task 1/2/3's discovery/manual-add).
- Produces: global `vsi_os` (one of `ibmi|aix|linux|other`, or `""` if the VSI wasn't found — though that case already aborts before use), set by `check_locally_VSI_exists`. This is what Task 5 consumes.

- [ ] **Step 1: Read current function bodies to confirm line numbers**

Run: `grep -n '^get_iASP_name() {\|^check_locally_VSI_exists() {' bluexport_api.sh`

- [ ] **Step 2: Replace `check_locally_VSI_exists`**

Replace (currently `bluexport_api.sh:1374-1399`):
```bash
check_locally_VSI_exists() {
	# Clear job log
	: > "$job_log"
	# Case-insensitive check if VSI exists in JSON
	if jq -e --arg vsi "$vsi" 'any(.systems[]; (.name | ascii_downcase) == ($vsi | ascii_downcase))' "$bluexscrt" > /dev/null
	then
		# Get workspace short name (e.g., WSMAD2) for this VSI (case-insensitive)
		vsiwsshort=$(jq -r --arg vsi "$vsi" '.systems[]	| select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | .workspace' "$bluexscrt")
		# Get workspace CRN for that short name
		shortnamecrn=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].crn' "$bluexscrt")
		# Call function that lists VSIs in that workspace (writes to $vsi_list_tmp)
		dc_vsi_list "$shortnamecrn"
		# Get the cloud VSI name from the list file (grep -wi já é case-insensitive)
		vsi_cloud_name=$(grep -wi "$vsi" "$vsi_list_tmp" | awk '{print $1}')
		# Get full workspace name directly from JSON
		full_ws_name=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].name' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi_cloud_name was found in $full_ws_name..." "1"
		if [ "$flagj" -eq 0 ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI to Capture: $vsi_cloud_name" "1"
			get_iASP_name
		fi	else
		echoscreen ""
		abort "   ### VSI $vsi not found in any of the workspaces available in $bluexscrt!"
	fi
}
```

With:
```bash
check_locally_VSI_exists() {
	# Clear job log
	: > "$job_log"
	vsi_os=""
	# Case-insensitive check if VSI exists in JSON
	if jq -e --arg vsi "$vsi" 'any(.systems[]; (.name | ascii_downcase) == ($vsi | ascii_downcase))' "$bluexscrt" > /dev/null
	then
		# Get workspace short name (e.g., WSMAD2) for this VSI (case-insensitive)
		vsiwsshort=$(jq -r --arg vsi "$vsi" '.systems[]	| select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | .workspace' "$bluexscrt")
		# Get OS category for this VSI (case-insensitive match on name). Only assigned
		# here, after existence is confirmed above - missing os field (pre-upgrade
		# .systems[] entries) falls back to ibmi, the only OS the tool ever stored
		# before this field existed.
		vsi_os=$(jq -r --arg vsi "$vsi" '.systems[] | select((.name | ascii_downcase) == ($vsi | ascii_downcase)) | (.os // "ibmi")' "$bluexscrt")
		# Get workspace CRN for that short name
		shortnamecrn=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].crn' "$bluexscrt")
		# Call function that lists VSIs in that workspace (writes to $vsi_list_tmp)
		dc_vsi_list "$shortnamecrn"
		# Get the cloud VSI name from the list file (grep -wi já é case-insensitive)
		vsi_cloud_name=$(grep -wi "$vsi" "$vsi_list_tmp" | awk '{print $1}')
		# Get full workspace name directly from JSON
		full_ws_name=$(jq -r --arg ws "$vsiwsshort" '.workspaces[$ws].name' "$bluexscrt")
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi_cloud_name was found in $full_ws_name..." "1"
		if [ "$flagj" -eq 0 ]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI to Capture: $vsi_cloud_name" "1"
			get_iASP_name
		fi	else
		echoscreen ""
		abort "   ### VSI $vsi not found in any of the workspaces available in $bluexscrt!"
	fi
}
```

- [ ] **Step 3: Replace `get_iASP_name`**

Replace (currently `bluexport_api.sh:1273-1370`):
```bash
get_iASP_name() {
	vsi_status=$(ins_get | jq -r '.status')
	shutoff=0
	if [ $test -eq 0 ]
	then
		vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .ip' "$bluexscrt")
		if [[ -z "$vsi_ip" || "$vsi_ip" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi not found in JSON systems[] section. Aborting..."
		fi
		# Detect local execution
		local_name=$(hostname -s 2>/dev/null)
		if [[ "$local_name" == "${vsi^^}" ]]
		then
			###################################################################
			# WE ARE RUNNING ON THE SAME VSI — NO PING, NO SSH, DIRECT EXECUTION
			###################################################################
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running locally on VSI $vsi — skipping ping and ssh checks." "1"
			if [[ "$vsi_status" == "SHUTOFF" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names locally..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(eval "$cmd")
		else
			###################################################################
			# REMOTE VSI — NORMAL FLOW (PING + SSH)
			###################################################################
			if [[ "$vsi_status" != "SHUTOFF" ]]
			then
				if [[ "$(uname -s)" == "OS400" ]]
				then
					PING="system \"PING RMTSYS('$vsi_ip') NBRPKT(1) WAITTIME(3)\""
				else
					PING="ping -c1 -w3 $vsi_ip"
				fi
				if eval $PING &> /dev/null
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Ping VSI $vsi at IP $vsi_ip OK." "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names..." "1"
				else
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - First ping to $vsi_ip failed, retrying..." "1"
					if ! eval $PING &> /dev/null
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - Cannot ping VSI $vsi at $vsi_ip ! Aborting..."
					fi
				fi
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			# SSH test (only remote)
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Trying to ssh into VSI $vsi..." "1"
			ssh -T -q -i "$sshkeypath" "$vsi_user@$vsi_ip" exit
			if [ $? -eq 255 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Unable to SSH to $vsi! Try STRTCPSVR *SSHD. Aborting..."
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - ssh into VSI $vsi succeeded..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "$cmd")
		fi
		###################################################################
		# COMMON BLOCK — PARSING iASP OUTPUT (LOCAL OR REMOTE)
		###################################################################
		iasp_name=$(echo "$iasp_output" | tail -n+4 | head -n-1 | awk '{print $1":"$3}')
		echo "" > "$iasp_names_file"
		for line in $iasp_name
		do
			line_status=$(echo "$line" | cut -d ":" -f2-)
			if [[ "$line_status" == "AVAILABLE" ]]
			then
				echo "$line" | cut -d: -f1 >> "$iasp_names_file"
			fi
		done
		iasp_names=$(cat "$iasp_names_file")
		if [[ -z "$iasp_names" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi has no AVAILABLE iASPs... Moving on..." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi iASP Names: $iasp_names" "1"
		fi
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running in test mode, skipping get iASP name." "1"
		if [[ "$vsi_status" == "SHUTOFF" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
			shutoff=1
			return
		fi
	fi
}
```

With:
```bash
get_iASP_name() {
	vsi_status=$(ins_get | jq -r '.status')
	shutoff=0
	if [ $test -eq 0 ]
	then
		vsi_ip=$(jq -r --arg name "$vsi" '.systems[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .ip' "$bluexscrt")
		if [[ -z "$vsi_ip" || "$vsi_ip" == "null" ]]
		then
			abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi not found in JSON systems[] section. Aborting..."
		fi
		# Detect local execution
		local_name=$(hostname -s 2>/dev/null)
		if [[ "$local_name" == "${vsi^^}" ]]
		then
			###################################################################
			# WE ARE RUNNING ON THE SAME VSI — NO PING, NO SSH, DIRECT EXECUTION
			###################################################################
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running locally on VSI $vsi — skipping ping and ssh checks." "1"
			if [[ "$vsi_status" == "SHUTOFF" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			if [[ "$vsi_os" != "ibmi" ]]
			then
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - skipping iASP discovery (IBM i-only, not applicable)." "1"
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
				return
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names locally..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(eval "$cmd")
		else
			###################################################################
			# REMOTE VSI — NORMAL FLOW (PING + SSH)
			###################################################################
			if [[ "$vsi_status" != "SHUTOFF" ]]
			then
				if [[ "$vsi_os" != "ibmi" ]]
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - skipping iASP discovery (IBM i-only, not applicable)." "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
					return
				fi
				if [[ "$(uname -s)" == "OS400" ]]
				then
					PING="system \"PING RMTSYS('$vsi_ip') NBRPKT(1) WAITTIME(3)\""
				else
					PING="ping -c1 -w3 $vsi_ip"
				fi
				if eval $PING &> /dev/null
				then
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is in Status: $vsi_status" "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Ping VSI $vsi at IP $vsi_ip OK." "1"
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Getting $vsi iASP Names..." "1"
				else
					echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - First ping to $vsi_ip failed, retrying..." "1"
					if ! eval $PING &> /dev/null
					then
						abort "$(date +%Y-%m-%d_%H:%M:%S) - Cannot ping VSI $vsi at $vsi_ip ! Aborting..."
					fi
				fi
			else
				echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
				shutoff=1
				return
			fi
			# SSH test (only remote)
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Trying to ssh into VSI $vsi..." "1"
			ssh -T -q -i "$sshkeypath" "$vsi_user@$vsi_ip" exit
			if [ $? -eq 255 ]
			then
				abort "$(date +%Y-%m-%d_%H:%M:%S) - Unable to SSH to $vsi! Try STRTCPSVR *SSHD. Aborting..."
			fi
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - ssh into VSI $vsi succeeded..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_output=$(ssh -T -i "$sshkeypath" "$vsi_user@$vsi_ip" "$cmd")
		fi
		###################################################################
		# COMMON BLOCK — PARSING iASP OUTPUT (LOCAL OR REMOTE)
		###################################################################
		iasp_name=$(echo "$iasp_output" | tail -n+4 | head -n-1 | awk '{print $1":"$3}')
		echo "" > "$iasp_names_file"
		for line in $iasp_name
		do
			line_status=$(echo "$line" | cut -d ":" -f2-)
			if [[ "$line_status" == "AVAILABLE" ]]
			then
				echo "$line" | cut -d: -f1 >> "$iasp_names_file"
			fi
		done
		iasp_names=$(cat "$iasp_names_file")
		if [[ -z "$iasp_names" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi has no AVAILABLE iASPs... Moving on..." "1"
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi iASP Names: $iasp_names" "1"
		fi
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - Running in test mode, skipping get iASP name." "1"
		if [[ "$vsi_status" == "SHUTOFF" ]]
		then
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is SHUTOFF" "1"
			shutoff=1
			return
		fi
	fi
}
```

(Only the two nested `if [[ "$vsi_os" != "ibmi" ]] ... return` blocks are new — one in the local-execution branch, one in the remote branch, both inserted right after their existing SHUTOFF check. Everything else is byte-for-byte identical to the original.)

- [ ] **Step 4: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 5: Write and run a mocked functional test**

Create `/tmp/test_get_iasp_name.sh`:

```bash
#!/bin/bash
set -uo pipefail
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/bin"

cat > "$WORKDIR/bin/ssh" <<'EOF'
#!/bin/bash
echo "SSH_CALLED $*" >> "$SSH_LOG"
if [[ "$*" == *" exit"* ]]; then
	exit 0
fi
echo "Work with Configuration Status"
echo ""
echo "Opt  Device        Status"
echo "TESTASP       CFGD        AVAILABLE"
echo "Bottom line filler"
EOF
chmod +x "$WORKDIR/bin/ssh"

cat > "$WORKDIR/bin/ping" <<'EOF'
#!/bin/bash
echo "PING_CALLED $*" >> "$PING_LOG"
exit 0
EOF
chmod +x "$WORKDIR/bin/ping"

export SSH_LOG="$WORKDIR/ssh.log"
export PING_LOG="$WORKDIR/ping.log"
: > "$SSH_LOG"
: > "$PING_LOG"
export PATH="$WORKDIR/bin:$PATH"

REPO=/home/rqmartins/Git/bluexport_api
source <(sed -n '/^get_iASP_name() {/,/^}/p' "$REPO/bluexport_api.sh")

ins_get() { echo '{"status":"ACTIVE"}'; }
echoscreen() { echo "LOG: $1"; }
abort() { echo "ABORT: $1"; exit 1; }

bluexscrt="$WORKDIR/systems.json"
cat > "$bluexscrt" <<'EOF'
{"systems":[{"name":"testvsi","ip":"10.0.0.5","os":"aix"}]}
EOF

vsi="testvsi"
vsi_user="testuser"
sshkeypath="/dev/null"
test=0
iasp_names_file="$WORKDIR/iasp_names.tmp"

fail=0

echo "=== Case 1: vsi_os=aix -> expect NO ping/ssh calls ==="
vsi_os="aix"
iasp_names=""
get_iASP_name
ssh_calls=$(wc -l < "$SSH_LOG")
ping_calls=$(wc -l < "$PING_LOG")
if [[ "$ssh_calls" == "0" && "$ping_calls" == "0" && "$shutoff" == "0" ]]; then
	echo "PASS: aix target made 0 ssh/ping calls, shutoff=0"
else
	echo "FAIL: aix target made $ssh_calls ssh calls, $ping_calls ping calls, shutoff=$shutoff (expected 0/0/0)"
	fail=1
fi

: > "$SSH_LOG"; : > "$PING_LOG"

echo "=== Case 2: vsi_os=ibmi -> expect ping+ssh calls and iasp_names populated ==="
vsi_os="ibmi"
iasp_names=""
get_iASP_name
ssh_calls=$(wc -l < "$SSH_LOG")
ping_calls=$(wc -l < "$PING_LOG")
if [[ "$ssh_calls" -ge 2 && "$ping_calls" -ge 1 && "$iasp_names" == "TESTASP" ]]; then
	echo "PASS: ibmi target made $ssh_calls ssh calls, $ping_calls ping calls, iasp_names=$iasp_names"
else
	echo "FAIL: ibmi target made $ssh_calls ssh calls, $ping_calls ping calls, iasp_names='$iasp_names' (expected >=2 ssh, >=1 ping, iasp_names=TESTASP)"
	fail=1
fi

if [[ $fail -eq 0 ]]; then
	echo "ALL PASS"
else
	echo "SOME TESTS FAILED"
	exit 1
fi
```

Run: `bash /tmp/test_get_iasp_name.sh`
Expected: `PASS:` for both cases, then `ALL PASS`.

- [ ] **Step 6: Clean up the verification script**

Run: `rm -f /tmp/test_get_iasp_name.sh`

- [ ] **Step 7: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
check_locally_VSI_exists/get_iASP_name: resolve and honor vsi_os

check_locally_VSI_exists now resolves vsi_os (os field from
.systems[], // "ibmi" fallback for pre-upgrade entries) only after
confirming the VSI exists. get_iASP_name skips its ping+SSH+WRKCFGSTS
iASP-discovery tail entirely for non-ibmi targets - no SSH
connectivity or key required for AIX/Linux in this path. The
OS-agnostic status/SHUTOFF check ahead of it is unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Gate `flush_asps`/CHGASPACT at the 3 call sites

**Files:**
- Modify: `bluexport_api.sh:1449-1450` (`do_snap_create`)
- Modify: `bluexport_api.sh:1729-1734` (`do_volume_clone_execute`)
- Modify: `bluexport_api.sh:6271-6277` (capture/export flow)

**Interfaces:**
- Consumes: global `vsi_os`, set by `check_locally_VSI_exists` (Task 4). All three call sites run after `check_locally_VSI_exists` has already executed in their respective flows (confirm this holds at each site during Step 1 below; do not assume — check the actual call order in the surrounding function/flow before editing).

- [ ] **Step 1: Confirm current line numbers and call order**

Run: `grep -n '^do_snap_create() {\|^do_volume_clone_execute() {\|	flush_asps\|check_locally_VSI_exists' bluexport_api.sh`

For each of the 3 flush_asps call sites, confirm `check_locally_VSI_exists` (or a code path that calls it) runs earlier in the same execution flow, so `vsi_os` is already set by the time the site is reached. If any site turns out NOT to be preceded by `check_locally_VSI_exists` in its actual call chain, stop and report this — do not guess.

- [ ] **Step 2: Gate `do_snap_create`**

Replace:
```bash
do_snap_create() {
	flush_asps
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" "1"
```

With:
```bash
do_snap_create() {
	if [[ "$vsi_os" == "ibmi" ]]
	then
		flush_asps
	else
		echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" "1"
```

- [ ] **Step 3: Gate `do_volume_clone_execute`**

Replace:
```bash
do_volume_clone_execute() {
	# Flush ASPs na origem antes de executar o clone
	if [[ $shutoff == "0" ]]
	then
		flush_asps
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Volume Clone with name $vclone_name ..." "1"
```

With:
```bash
do_volume_clone_execute() {
	# Flush ASPs na origem antes de executar o clone (IBM i only)
	if [[ $shutoff == "0" ]]
	then
		if [[ "$vsi_os" == "ibmi" ]]
		then
			flush_asps
		else
			echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
		fi
	fi
	echoscreen "$(date +%Y-%m-%d_%H:%M:%S) - == Executing Volume Clone with name $vclone_name ..." "1"
```

- [ ] **Step 4: Gate the capture/export flow**

Replace:
```bash
####  START: Flush ASPs and iASP Memory to Disk  ####
if [ $shutoff -eq 0 ]
then
	flush_asps
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Skipping Flushing Memory to Disk..." "1"
fi

####  END: Flush ASPs and iASP Memory to Disk  ####
```

With:
```bash
####  START: Flush ASPs and iASP Memory to Disk  ####
if [ $shutoff -eq 0 ]
then
	if [[ "$vsi_os" == "ibmi" ]]
	then
		flush_asps
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is $vsi_os - CHGASPACT not applicable, skipping ASP flush." "1"
	fi
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Skipping Flushing Memory to Disk..." "1"
fi

####  END: Flush ASPs and iASP Memory to Disk  ####
```

- [ ] **Step 5: Syntax check**

Run: `bash -n bluexport_api.sh`
Expected: no output.

- [ ] **Step 6: Write and run a standalone logic-replication test**

This does not exercise the full functions (they have many other runtime dependencies not worth mocking three times); it proves the exact conditional logic added at each site behaves correctly for every `vsi_os`/`shutoff` combination. End-to-end proof against the real script happens in Task 7.

Create `/tmp/test_chgaspact_gate.sh`:

```bash
#!/bin/bash
set -uo pipefail

flush_asps() { echo "FLUSH_ASPS_CALLED"; }
echoscreen() { echo "SKIP_MSG: $1"; }

# Replicates the do_snap_create gate (Step 2)
snap_gate() {
	local vsi_os="$1"
	if [[ "$vsi_os" == "ibmi" ]]
	then
		flush_asps
	else
		echoscreen "VSI test is $vsi_os - CHGASPACT not applicable, skipping ASP flush."
	fi
}

# Replicates the do_volume_clone_execute gate (Step 3)
clone_gate() {
	local shutoff="$1" vsi_os="$2"
	if [[ $shutoff == "0" ]]
	then
		if [[ "$vsi_os" == "ibmi" ]]
		then
			flush_asps
		else
			echoscreen "VSI test is $vsi_os - CHGASPACT not applicable, skipping ASP flush."
		fi
	fi
}

fail=0

out=$(snap_gate "ibmi")
[[ "$out" == "FLUSH_ASPS_CALLED" ]] && echo "PASS: snap_gate ibmi -> flush_asps called" || { echo "FAIL: snap_gate ibmi -> got '$out'"; fail=1; }

out=$(snap_gate "aix")
[[ "$out" == "SKIP_MSG: VSI test is aix - CHGASPACT not applicable, skipping ASP flush." ]] && echo "PASS: snap_gate aix -> skipped with message" || { echo "FAIL: snap_gate aix -> got '$out'"; fail=1; }

out=$(clone_gate "0" "ibmi")
[[ "$out" == "FLUSH_ASPS_CALLED" ]] && echo "PASS: clone_gate shutoff=0 ibmi -> flush_asps called" || { echo "FAIL: clone_gate shutoff=0 ibmi -> got '$out'"; fail=1; }

out=$(clone_gate "0" "linux")
[[ "$out" == "SKIP_MSG: VSI test is linux - CHGASPACT not applicable, skipping ASP flush." ]] && echo "PASS: clone_gate shutoff=0 linux -> skipped with message" || { echo "FAIL: clone_gate shutoff=0 linux -> got '$out'"; fail=1; }

out=$(clone_gate "1" "ibmi")
[[ -z "$out" ]] && echo "PASS: clone_gate shutoff=1 ibmi -> nothing called (matches original shutoff guard)" || { echo "FAIL: clone_gate shutoff=1 ibmi -> got '$out'"; fail=1; }

if [[ $fail -eq 0 ]]; then
	echo "ALL PASS"
else
	echo "SOME TESTS FAILED"
	exit 1
fi
```

Run: `bash /tmp/test_chgaspact_gate.sh`
Expected: 5 `PASS:` lines followed by `ALL PASS`.

- [ ] **Step 7: Clean up the verification script**

Run: `rm -f /tmp/test_chgaspact_gate.sh`

- [ ] **Step 8: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexport_api.sh
git commit -m "$(cat <<'EOF'
Gate CHGASPACT (flush_asps) on vsi_os == ibmi at all 3 call sites

do_snap_create, do_volume_clone_execute, and the capture/export flow
now skip flush_asps for non-ibmi targets, logging why instead. Where
a shutoff guard already existed, vsi_os is an additional condition,
not a replacement - a SHUTOFF VSI still skips the flush regardless
of OS, exactly as before.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Version bumps, CHANGELOG, README

**Files:**
- Modify: `bluexscrt_config_api.sh:10` (`VERSION`)
- Modify: `bluexport_api.sh:143` (`Version`)
- Modify: `CHANGELOG.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (documentation/metadata only). Run this task last, after Tasks 1-5 are committed.

- [ ] **Step 1: Bump `bluexscrt_config_api.sh` VERSION**

Change `VERSION="<current>"` to `VERSION="2.0"` (MAJOR — `-addlpar` breaking change). Confirm the current value first with `grep -n '^VERSION=' bluexscrt_config_api.sh` in case it has changed since this plan was written.

- [ ] **Step 2: Bump `bluexport_api.sh` Version**

Change `Version=<current>` to `Version=1.13.0` (MINOR — additive). Confirm the current value first with `grep -n '^Version=' bluexport_api.sh`.

- [ ] **Step 3: Add CHANGELOG.md entries**

Read `CHANGELOG.md` first to find the current `## [Unreleased]` section and the most recent version entries (to match formatting/style), then add two new entries directly under `## [Unreleased]` (which stays empty/templated as-is), following the existing per-file-annotated style used by recent entries (e.g. `## [1.12.1] - 2026-08-04` with a `### Fixed (`bluexport_api.sh`)` sub-heading):

```markdown
## [2.0] - 2026-08-05 (`bluexscrt_config_api.sh`)

### Added
- LPAR discovery (`-updlpars`, and transitively `-updws`/`-createconfig`) is no longer IBM i-only: every LPAR in every configured workspace is now discovered and classified as `os`: `ibmi` | `aix` | `linux` | `other` (raw API value kept in `osDetail`). Unrecognized `osType` values classify as `other`, never assumed `linux`.
- `create_vsi_user_from_json` (optional step of `-createconfig`) filters to `os == ibmi` only, since SSH user provisioning via `DSPUSRPRF`/`CRTUSRPRF` is IBM i-only CL; skipped non-IBM i entries are reported by count.

### Changed
- **Breaking:** `-addlpar` now requires a 5th argument, `OS` (`ibmi|aix|linux|other`). Old 4-argument invocations now fail with a syntax error instead of silently assuming `ibmi`.

### Upgrade notes
- Run `-updlpars` once after upgrading to backfill `os`/`osDetail` on any `.systems[]` entry that predates this field (until then, such entries are treated as `ibmi` wherever read, since that was the only OS ever stored before).

## [1.13.0] - 2026-08-05 (`bluexport_api.sh`)

### Added
- `CHGASPACT` (the IBM i ASP-flush before snapshot create, volume clone execute, and image/cloud-storage capture) now only runs when the target LPAR's `os` (from `.systems[]`) is `ibmi`. For `aix`/`linux`/`other` targets, the flush is skipped with a log message, and the IBM i-only ping+SSH+`WRKCFGSTS` iASP-discovery step inside `get_iASP_name` is skipped entirely - no SSH connectivity or key is required for non-IBM i targets in these 3 operations.
- Purely additive: any installation with only IBM i entries in `.systems[]` sees no behavior change (missing `os` field falls back to `ibmi`).
```

- [ ] **Step 4: Update README.md**

Read `README.md` first to find the current `-updlpars`/`-addlpar` documentation and the snapshot/volume-clone/capture sections (search for `-updlpars`, `-addlpar`, `CHGASPACT` if present), then:
- Update the `-updlpars`/`-addlpar` syntax/description to match the new behavior (mirror the `usage()` text changes from Task 1 Step 5 and Task 2 Step 3).
- Add a short note near the snapshot/volume-clone/capture documentation explaining that ASP flush (`CHGASPACT`) only applies to IBM i LPARs; AIX/Linux targets skip it automatically based on the LPAR's recorded `os`.

- [ ] **Step 5: Syntax check both scripts one more time**

Run: `bash -n bluexscrt_config_api.sh && bash -n bluexport_api.sh && echo "SYNTAX OK"`
Expected: `SYNTAX OK`

- [ ] **Step 6: Commit**

```bash
cd /home/rqmartins/Git/bluexport_api
git add bluexscrt_config_api.sh bluexport_api.sh CHANGELOG.md README.md
git commit -m "$(cat <<'EOF'
Version bump + docs for multi-OS LPAR support

bluexscrt_config_api.sh -> 2.0 (MAJOR: -addlpar breaking change).
bluexport_api.sh -> 1.13.0 (MINOR: additive CHGASPACT gating).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Real-world verification (required before calling this done)

Not a code task — this is the acceptance checklist against the user's real IBM Cloud account and, separately, real IBM i PASE. Every sandbox test above proves logic only; none of it proves PASE execution or real API behavior. Do not skip this and do not report the feature as "done" without it.

**Prerequisites:** the user has explicitly authorized real (non-dry-run) testing against their `AIX` (workspace WSFRA1) and `PAO` (workspace WSMAD2, RHEL) PowerVS instances — both confirmed disposable/test instances. Do not test against any other real instance without separately asking.

- [ ] **Step 1: Run `-updlpars` for real and inspect the result**

```bash
./bluexscrt_config_api.sh -updlpars
```

Confirm in the output/masked config: `IBMiCC`/`IBMi75F1`/`IBMi75M2`/`IBMiCCDR` classified `os:"ibmi"`; `AIX` classified `os:"aix"`; `PAO`/`nfs` classified `os:"linux"` with `osDetail` matching the raw API value seen earlier this session. Confirm pre-existing IBM i entries in the JSON now show `os:"ibmi"` explicitly (the backfill).

- [ ] **Step 2: Dry-run capture against the AIX and RHEL test instances**

```bash
./bluexport_api.sh -ta AIX AIX_test_img image-catalog hourly
./bluexport_api.sh -ta PAO PAO_test_img image-catalog hourly
```

(Adjust flags to match this repo's actual `-ta` syntax if it differs - check `./bluexport_api.sh -h` first.) Confirm the log shows `VSI ... is aix/linux - CHGASPACT not applicable, skipping ASP flush.` and no SSH/ping attempt for the iASP step, with the rest of the dry-run flow completing normally (no real `ins_cap` call, since `-ta` is test mode).

- [ ] **Step 3: Regression check - dry-run capture against a real IBM i instance**

```bash
./bluexport_api.sh -ta IBMi75M2 IBMi75M2_test_img image-catalog hourly
```

Confirm CHGASPACT still fires as before (or, in test mode, the "Simulating Flushing Memory to Disk" message still appears) - proving existing IBM i behavior is unchanged.

- [ ] **Step 4: Real snapshot-create test against AIX or PAO (no test-mode coverage exists for this flag)**

Run `-snapcr` against `AIX` or `PAO` per this repo's actual syntax (check `./bluexport_api.sh -h`). Confirm the log shows the ASP-flush-skipped message and the snapshot completes. Clean up afterward with `-snapdel`.

- [ ] **Step 5: Real volume-clone test against AIX or PAO (no test-mode coverage exists for this flag)**

Run `-vclone` against `AIX` or `PAO` per this repo's actual syntax. Confirm the log shows the ASP-flush-skipped message and the clone completes. Clean up afterward with `-vclonedel`.

- [ ] **Step 6: Real verification on IBM i PASE**

Deploy the updated scripts to the real IBM i PASE environment (via `gitpush_v2` once the user confirms) and repeat Steps 1-3 there, at minimum. Report explicitly whether this ran on PASE or only in a Linux/sandbox environment - do not claim PASE verification without having actually run it there, per standing project guidance.

- [ ] **Step 7: Report results to the user**

Summarize what was confirmed at each step above, any deviations from expected behavior, and get explicit sign-off before considering this feature complete.

---

## Self-Review Notes

- **Spec coverage:** Section A (data model) → Task 1. Section B (discovery) → Task 1. Section C (`-addlpar`) → Task 2. Section D (`check_locally_VSI_exists`/`get_iASP_name`) → Task 4. Section E (CHGASPACT gate) → Task 5. Section F (`create_vsi_user_from_json`) → Task 3. Section G (docs) → Task 6. Section H (testing) → embedded per-task tests + Task 7. Versioning section → Task 6. All spec sections have a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code or an exact command.
- **Type/name consistency:** `vsi_os` is the single name used everywhere it's produced (Task 4) and consumed (Task 5) — checked against both edits above. `os`/`osDetail` field names are identical across Task 1 (discovery), Task 2 (`-addlpar`), Task 3 (`create_vsi_user_from_json` reads `.os`), and Task 4 (`check_locally_VSI_exists` reads `.os`).
- **Line numbers:** every task's Step 1 re-confirms current line numbers with `grep`/`git diff` before editing, since both files have already shifted multiple times this session — do not trust the line numbers cited in prose, only the exact `old_string`/`new_string` content blocks.

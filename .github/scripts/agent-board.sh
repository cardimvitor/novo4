#!/usr/bin/env bash
# Quadro compartilhado dos agentes: um JSON por Issue em .agents/tasks/.
#
#   check <issue>                              falha se a Issue já tem agente em andamento ou PR aberto
#   start <agente> <issue>                     registra in-progress
#   finish <agente> <issue> <url_pr> <arquivo> registra pr-open com a explicação
#   show                                       imprime o quadro (para o prompt do agente)
#   claude-finish <issue>                      acha o PR aberto pelo Claude e registra pr-open
#
# Lê e escreve numa worktree do origin/<branch padrão>, então não mexe no branch do agente.
set -euo pipefail

BASE="${DEFAULT_BRANCH:-main}"
DIR=".agents/tasks"
TMP="${RUNNER_TEMP:-/tmp}/agent-board"
BOT_NAME="github-actions[bot]"
BOT_MAIL="41898282+github-actions[bot]@users.noreply.github.com"

fetch_board() {
  git fetch -q origin "$BASE"
  git worktree remove --force "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
  git worktree add -q --detach "$TMP" "origin/$BASE"
}

drop_board() {
  git worktree remove --force "$TMP" 2>/dev/null || rm -rf "$TMP"
}

# Aplica uma escrita no quadro e publica no branch padrão. Tenta de novo se outro workflow publicou antes.
write_board() {  # $1 = mensagem de commit ; demais = comando que altera o quadro dentro de $TMP
  local message="$1"; shift
  local attempt
  for attempt in 1 2 3 4; do
    fetch_board
    (cd "$TMP" && mkdir -p "$DIR" && "$@")
    if (cd "$TMP" && git add "$DIR" && ! git diff --cached --quiet); then
      if (cd "$TMP" && git -c user.name="$BOT_NAME" -c user.email="$BOT_MAIL" commit -q -m "$message" \
        && git push -q origin "HEAD:refs/heads/$BASE"); then
        drop_board
        return 0
      fi
    else
      drop_board
      return 0
    fi
    sleep $((attempt * 3))
  done
  drop_board
  echo "Não foi possível publicar o quadro em $BASE." >&2
  exit 1
}

task_path() { echo "$TMP/$DIR/issue-$1.json"; }

status_of() {  # $1 = issue ; imprime o status atual ou vazio
  local path; path="$(task_path "$1")"
  if [ -f "$path" ]; then
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$path"
  fi
}

cmd_check() {
  local issue="$1"
  # Um comentário com a menção é um pedido explícito de alguém (ex.: ajustar o PR), então não bloqueia.
  if [ "${GITHUB_EVENT_NAME:-}" = "issue_comment" ]; then
    echo "Evento de comentário: pedido explícito, o quadro não bloqueia."
    return 0
  fi
  fetch_board
  local status; status="$(status_of "$issue")"
  drop_board
  if [ "$status" = "in-progress" ] || [ "$status" = "pr-open" ]; then
    echo "A Issue #$issue já está com status '$status' no quadro. Não executo de novo." >&2
    exit 1
  fi
  echo "Issue #$issue livre no quadro."
}

write_task_python='
import json, sys, datetime
path, agent, issue, status, extra = sys.argv[1:6]
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
data = {"issue": int(issue), "agent": agent, "status": status, "updated_at": now}
if status == "in-progress":
    data["branch"] = f"agent/{agent}-issue-{issue}"
    data["started_at"] = now
else:
    url, explanation = extra.split("\n", 1)
    data["pr"] = url
    data["explanation"] = explanation
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
'

cmd_start() {
  local agent="$1" issue="$2"
  write_board "board: $agent inicia issue #$issue" \
    python3 -c "$write_task_python" "$(task_path "$issue")" "$agent" "$issue" "in-progress" ""
  echo "Quadro: issue #$issue em andamento por $agent."
}

cmd_finish() {
  local agent="$1" issue="$2" url="$3" explanation_file="$4"
  local explanation; explanation="$(cat "$explanation_file")"
  write_board "board: $agent abriu PR para issue #$issue" \
    python3 -c "$write_task_python" "$(task_path "$issue")" "$agent" "$issue" "pr-open" "$url"$'\n'"$explanation"
  echo "Quadro: issue #$issue com PR aberto ($url)."
}

cmd_show() {
  fetch_board
  python3 - "$TMP/$DIR" <<'PY'
import glob, json, os, sys
folder = sys.argv[1]
files = sorted(glob.glob(os.path.join(folder, "issue-*.json")))
if not files:
    print("Quadro vazio: nenhuma tarefa em andamento.")
for path in files:
    t = json.load(open(path))
    line = f"- Issue #{t.get('issue')} | agente: {t.get('agent')} | status: {t.get('status')}"
    if t.get("pr"):
        line += f" | PR: {t['pr']}"
    print(line)
    if t.get("explanation"):
        print("  " + t["explanation"].splitlines()[0][:200])
PY
  drop_board
}

cmd_claude_finish() {
  local issue="$1"
  local prs found number url body explanation_file files
  prs="$(gh pr list --state open --limit 100 --json number,url,headRefName)"
  found="$(python3 -c '
import json, sys
issue = sys.argv[1]
for pr in json.load(sys.stdin):
    if pr["headRefName"].startswith(f"claude/issue-{issue}-"):
        print(pr["number"], pr["url"], sep="\t")
        break
' "$issue" <<<"$prs")"
  if [ -z "$found" ]; then
    echo "Nenhum PR aberto do Claude para a issue #$issue. Nada a registrar."
    return 0
  fi
  number="$(cut -f1 <<<"$found")"
  url="$(cut -f2 <<<"$found")"
  explanation_file="${RUNNER_TEMP:-/tmp}/claude-explanation.md"
  body="$(gh pr view "$number" --json body --jq .body)"
  if grep -q "## Para os outros agentes" <<<"$body"; then
    python3 -c 'import sys,re; b=sys.stdin.read(); m=re.search(r"## Para os outros agentes\n(.*?)(\n## |\Z)", b, re.S); print((m.group(1) if m else "").strip())' <<<"$body" > "$explanation_file"
  else
    files="$(gh pr view "$number" --json files --jq '.files[].path' | sed 's/^/- /')"
    printf 'O Claude não escreveu a explicação. Arquivos alterados:\n%s\n' "$files" > "$explanation_file"
    gh pr edit "$number" --body "$(printf '%s\n\n## Para os outros agentes\n%s\n' "$body" "$(cat "$explanation_file")")"
  fi
  cmd_finish claude "$issue" "$url" "$explanation_file"
}

case "${1:-}" in
  check) cmd_check "$2" ;;
  start) cmd_start "$2" "$3" ;;
  finish) cmd_finish "$2" "$3" "$4" "$5" ;;
  show) cmd_show ;;
  claude-finish) cmd_claude_finish "$2" ;;
  *) echo "uso: agent-board.sh {check|start|finish|show|claude-finish} ..." >&2; exit 2 ;;
esac

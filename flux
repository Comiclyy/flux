#!/usr/bin/env bash
#
# flux — git, but simple.
#
#   flux -s            save everything: pull, commit, push
#   flux sync          pull the latest changes
#   flux help          see everything else
#
set -o pipefail

VERSION="2.0.0"
ASSUME_YES=0

# ─── Colors (off when piped or NO_COLOR is set) ───────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'
  CLEAR_LINE=$'\r\033[K'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
  CLEAR_LINE=$'\n'
fi

# ─── Output helpers ───────────────────────────────────────────────────────────
info()  { printf "%s\n" "  ${BLUE}•${RESET} $*"; }
warn()  { printf "%s\n" "  ${YELLOW}!${RESET} $*"; }
ok()    { printf "%s\n" "  ${GREEN}✓${RESET} $*"; }
hint()  { printf "%s\n" "    ${DIM}→ $*${RESET}"; }
fail()  { printf "%s\n" "  ${RED}✗${RESET} $*" >&2; exit 1; }
done_msg() { printf "\n%s\n" "${BOLD}${GREEN}DONE${RESET} ${DIM}$*${RESET}"; }

# Run a command as a named step. Quiet on success; shows git's real output on
# failure so you know what went wrong. Extra hint lines follow a "--".
#   step "Pulling" -- git pull || ...
step() {
  local label=$1; shift
  local hints=()
  while [[ $# -gt 0 && $1 != "--" ]]; do hints+=("$1"); shift; done
  shift # drop "--"

  printf "%s" "  ${CYAN}…${RESET} ${label}"
  local output
  if output=$("$@" 2>&1); then
    printf "%s\n" "${CLEAR_LINE}  ${GREEN}✓${RESET} ${label}"
    return 0
  fi
  printf "%s\n" "${CLEAR_LINE}  ${RED}✗${RESET} ${label} ${RED}failed${RESET}"
  [[ -n $output ]] && printf "%s\n" "$output" | sed "s/^/    ${DIM}│${RESET} /"
  local h
  for h in "${hints[@]}"; do hint "$h"; done
  exit 1
}

confirm() {
  [[ $ASSUME_YES -eq 1 ]] && return 0
  local reply
  read -r -p "  ${YELLOW}?${RESET} $1 ${DIM}[y/N]${RESET} " reply
  [[ $reply =~ ^[Yy] ]]
}

# ─── Git helpers ──────────────────────────────────────────────────────────────
require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail "This folder isn't a git repository.$(printf '\n')    ${DIM}→ Run 'git init' to start one, or cd into a project.${RESET}"
}

current_branch() { git symbolic-ref --short -q HEAD || echo "(detached)"; }
# Upstream branch (e.g. origin/main), only if it actually exists on the remote.
upstream() {
  local up
  up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || return 0
  git rev-parse -q --verify "refs/remotes/$up" >/dev/null && echo "$up"
}
has_commits()    { git rev-parse -q --verify HEAD >/dev/null 2>&1; }
default_remote() {
  local remotes
  remotes=$(git remote)
  if grep -qx origin <<<"$remotes"; then echo origin; else head -n1 <<<"$remotes"; fi
}

# Prints "<behind> <ahead>" relative to upstream.
behind_ahead() { git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null; }

pull_latest() {
  local remote up
  remote=$(default_remote)
  if [[ -z $remote ]]; then
    warn "No remote set up — working locally only."
    hint "Add one with: git remote add origin <url>"
    return 0
  fi

  step "Fetching from ${remote}" -- git fetch --prune "$remote"

  up=$(upstream)
  if [[ -z $up ]]; then
    info "Branch ${BOLD}$(current_branch)${RESET} isn't on ${remote} yet — nothing to pull."
    return 0
  fi

  step "Pulling from ${up}" \
    "If it's a conflict: fix the files above, then run: git add -A && git rebase --continue" \
    "Or back out with: git rebase --abort" \
    -- git pull --rebase --autostash
}

push_changes() {
  local remote up
  remote=$(default_remote)
  [[ -z $remote ]] && return 0
  up=$(upstream)
  if [[ -z $up ]]; then
    step "Publishing $(current_branch) to ${remote}" -- git push -u "$remote" HEAD
  else
    step "Pushing to ${up}" \
      "Someone may have pushed in the meantime — run 'flux -s' again." \
      -- git push
  fi
}

# Builds a commit message from the staged file names, e.g.
# "Update app.js, styles.css (+3 more)"
auto_message() {
  local files count shown
  files=$(git diff --cached --name-only)
  count=$(grep -c . <<<"$files")
  shown=$(head -n 2 <<<"$files" | xargs -n1 basename | paste -sd ',' - | sed 's/,/, /g')
  if (( count > 2 )); then
    echo "Update ${shown} (+$((count - 2)) more)"
  else
    echo "Update ${shown}"
  fi
}

show_staged() {
  local lines total
  lines=$(git -c color.status=always status --short)
  total=$(grep -c . <<<"$lines")
  printf "\n"
  head -n 15 <<<"$lines" | sed 's/^/    /'
  (( total > 15 )) && printf "%s\n" "    ${DIM}…and $((total - 15)) more${RESET}"
  printf "\n"
}

# ─── Commands ─────────────────────────────────────────────────────────────────
cmd_save() {
  require_repo
  local message="$*"

  pull_latest
  step "Staging all changes" -- git add -A

  if git diff --cached --quiet; then
    local counts ahead=0
    counts=$(behind_ahead) && ahead=${counts##*[[:space:]]}
    if (( ahead > 0 )); then
      info "No new changes, but ${ahead} commit(s) haven't been pushed yet."
      push_changes
      done_msg "Everything is pushed."
    else
      done_msg "Nothing to save — you're all up to date."
    fi
    return 0
  fi

  show_staged

  local suggested
  suggested=$(auto_message)
  if [[ -z $message ]]; then
    if [[ $ASSUME_YES -eq 1 || ! -t 0 ]]; then
      message=$suggested
    else
      printf "%s\n" "  ${BOLD}Commit message${RESET} ${DIM}(Enter to use: \"${suggested}\")${RESET}"
      read -r -e -p "  ${CYAN}›${RESET} " message
      [[ -z $message ]] && message=$suggested
    fi
  fi

  step "Committing" -- git commit -m "$message"
  push_changes

  done_msg "Saved $(git rev-parse --short HEAD) on $(current_branch): \"${message}\""
}

cmd_sync() {
  require_repo
  pull_latest
  done_msg "$(current_branch) is up to date."
}

cmd_status() {
  require_repo
  local branch up counts behind ahead
  branch=$(current_branch)
  up=$(upstream)

  printf "\n  ${BOLD}On branch${RESET} ${CYAN}%s${RESET}" "$branch"
  if [[ -n $up ]] && counts=$(behind_ahead); then
    behind=${counts%%[[:space:]]*}
    ahead=${counts##*[[:space:]]}
    printf " ${DIM}→ %s${RESET}\n" "$up"
    (( ahead  > 0 )) && info "${ahead} commit(s) to push"
    (( behind > 0 )) && info "${behind} commit(s) to pull ${DIM}(run: flux sync)${RESET}"
    (( ahead == 0 && behind == 0 )) && ok "In sync with ${up} ${DIM}(as of last fetch)${RESET}"
  else
    printf " ${DIM}(not pushed anywhere yet)${RESET}\n"
  fi

  if [[ -z $(git status --porcelain) ]]; then
    ok "No uncommitted changes"
  else
    info "Uncommitted changes:"
    printf "%s\n" "$(git -c color.status=always status --short)" | sed 's/^/    /'
    hint "Save them with: flux -s"
  fi
  printf "\n"
}

cmd_log() {
  require_repo
  has_commits || fail "No commits yet."
  local n=${1:-10}
  [[ $n =~ ^[0-9]+$ ]] || fail "Usage: flux log [number]"
  git --no-pager log -n "$n" --graph --color=auto \
    --format="%C(yellow)%h%C(reset) %s %C(dim)— %an, %cr%C(reset)%C(auto)%d%C(reset)"
}

cmd_diff() {
  require_repo
  if has_commits; then git diff HEAD "$@"; else git diff --cached "$@"; fi
  local untracked
  untracked=$(git ls-files --others --exclude-standard)
  if [[ -n $untracked ]]; then
    printf "\n%s\n" "  ${BOLD}New files:${RESET}"
    sed "s/^/    ${GREEN}+${RESET} /" <<<"$untracked"
  fi
}

cmd_undo() {
  require_repo
  has_commits || fail "No commits to undo."
  git rev-parse -q --verify 'HEAD~1' >/dev/null ||
    fail "That's the very first commit — there's nothing before it to go back to."

  local last up
  last=$(git log -1 --format='%h "%s"')
  up=$(upstream)
  printf "\n  Last commit: ${YELLOW}%s${RESET}\n" "$last"
  if [[ -n $up ]] && git merge-base --is-ancestor HEAD "$up" 2>/dev/null; then
    warn "This commit is already pushed. Undo only changes your copy — the next sync will bring it back."
  fi
  confirm "Undo it? Your changes stay in your files." || { info "Cancelled."; return 0; }

  step "Undoing last commit" -- git reset --soft HEAD~1
  done_msg "Commit removed. Your changes are still there — edit and 'flux -s' again."
}

cmd_branch() {
  require_repo
  local name=$1 remote
  if [[ -z $name ]]; then
    git --no-pager branch --sort=-committerdate \
      --format="  %(if)%(HEAD)%(then)${GREEN}*%(else) %(end) %(refname:short)${RESET} ${DIM}%(committerdate:relative)${RESET}"
    hint "Switch or create with: flux branch <name>"
    return 0
  fi

  if git show-ref --verify --quiet "refs/heads/$name"; then
    step "Switching to ${name}" \
      "Save or stash your changes first: flux -s" \
      -- git switch "$name"
  elif remote=$(default_remote) && [[ -n $remote ]] &&
       git show-ref --verify --quiet "refs/remotes/$remote/$name"; then
    step "Checking out ${name} from ${remote}" -- git switch --track "$remote/$name"
  else
    confirm "Branch '${name}' doesn't exist. Create it?" || { info "Cancelled."; return 0; }
    step "Creating ${name}" -- git switch -c "$name"
  fi
  done_msg "Now on ${name}."
}

cmd_open() {
  require_repo
  local remote url
  remote=$(default_remote)
  [[ -z $remote ]] && fail "No remote set up to open."
  url=$(git remote get-url "$remote")
  # git@github.com:user/repo.git  →  https://github.com/user/repo
  url=$(sed -E -e 's#^git@([^:]+):#https://\1/#' -e 's#^ssh://git@#https://#' -e 's#\.git$##' <<<"$url")
  info "Opening ${url}"
  if command -v open >/dev/null; then open "$url"
  elif command -v xdg-open >/dev/null; then xdg-open "$url" >/dev/null 2>&1
  else printf "%s\n" "$url"
  fi
}

cmd_help() {
  cat <<EOF

  ${BOLD}flux${RESET} ${DIM}v${VERSION}${RESET} — git, but simple.

  ${BOLD}The two you need${RESET}
    ${GREEN}flux -s${RESET} ${DIM}[message]${RESET}       Save everything: pull, commit all, push
    ${GREEN}flux sync${RESET}               Get the latest changes

  ${BOLD}Look around${RESET}
    ${GREEN}flux status${RESET}             What's changed and what needs pushing
    ${GREEN}flux diff${RESET}               See exactly what you changed
    ${GREEN}flux log${RESET} ${DIM}[n]${RESET}            Recent commits (default 10)
    ${GREEN}flux open${RESET}               Open the repo in your browser

  ${BOLD}Fix & organize${RESET}
    ${GREEN}flux undo${RESET}               Undo last commit, keep your changes
    ${GREEN}flux branch${RESET} ${DIM}[name]${RESET}      List branches, or switch/create one

  ${BOLD}Options${RESET}
    ${GREEN}-y${RESET}, ${GREEN}--yes${RESET}               Skip questions (uses auto commit message)

  ${BOLD}Examples${RESET}
    flux -s                   ${DIM}# asks for a message (Enter = auto)${RESET}
    flux -s "fix login bug"   ${DIM}# no questions asked${RESET}
    flux branch new-feature   ${DIM}# make a branch and hop on it${RESET}

  ${DIM}Short forms: s/save, st, l, d, b, u — e.g. 'flux st'${RESET}

EOF
}

# ─── Entry point ──────────────────────────────────────────────────────────────
args=()
for arg in "$@"; do
  case $arg in
    -y|--yes) ASSUME_YES=1 ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

command=${1:-}
shift 2>/dev/null

case $command in
  -s|s|save|commit|c)   cmd_save "$@" ;;
  sync|pull|p)          cmd_sync ;;
  status|st)            cmd_status ;;
  log|l|history)        cmd_log "$@" ;;
  diff|d)               cmd_diff "$@" ;;
  undo|u)               cmd_undo ;;
  branch|b|switch|sw)   cmd_branch "$@" ;;
  open|web)             cmd_open ;;
  help|-h|--help)       cmd_help ;;
  version|-v|--version) echo "flux ${VERSION}" ;;
  "")
    # No arguments: show where things stand, plus a nudge toward the basics.
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      cmd_status
      printf "%s\n\n" "  ${DIM}flux -s to save · flux sync to pull · flux help for more${RESET}"
    else
      cmd_help
    fi
    ;;
  *)
    printf "%s\n" "  ${RED}✗${RESET} Unknown command: ${BOLD}${command}${RESET}" >&2
    hint "Try 'flux -s' to save, 'flux sync' to pull, or 'flux help' for everything."
    exit 1
    ;;
esac

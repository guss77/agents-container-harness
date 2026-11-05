#!/bin/bash -ex

function run_claude() {
CLAUDE_ARGS=(
--allow-dangerously-skip-permissions
--dangerously-skip-permissions
--allowedTools "*"
--permission-mode acceptEdits
-n aicode
)

if [ -z "$NEW_SESSION" ]; then
	CLAUDE_ARGS+=(--continue)
fi

UPDATE_MARKER="$HOME/.config/claude_last_update"
if [ ! -f "$UPDATE_MARKER" ] || [ $(( $(date +%s) - $(cat "$UPDATE_MARKER") )) -ge 604800 ]; then
  claude update
  date +%s > "$UPDATE_MARKER"
fi
claude ${CLAUDE_ARGS[@]}
}

function run_opencode() {
	OPENCODE_ARGS=(
		--auto
	)

	if [ -z "$NEW_SESSION" ]; then
		OPENCODE_ARGS+=(--continue)
	fi

	UPDATE_MARKER="$HOME/.config/opencode_last_update"
	if [ ! -f "$UPDATE_MARKER" ] || [ $(( $(date +%s) - $(cat "$UPDATE_MARKER") )) -ge 604800 ]; then
		~/.opencode/bin/opencode update
		date +%s > "$UPDATE_MARKER"
	fi

	~/.opencode/bin/opencode ${OPENCODE_ARGS[@]}
}

export PATH="$HOME/.local/bin:$PATH"
set -o allexport
source /.env
[ -f "$HOME/.config/.env" ] && source "$HOME/.config/.env"

cd $HOME
mkdir -p Projects
cd Projects

# setup git
[ -n "$GIT_EMAIL" ] && git config --global user.email "$GIT_EMAIL"
[ -n "$GIT_NAME" ] && git config --global user.name "$GIT_NAME"

set -x

case "${AI_COMMAND}" in
	opencode)
		run_opencode;;
	*)
		run_claude;;
esac


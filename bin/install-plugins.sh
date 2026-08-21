#!/usr/bin/env bash
# vim: ft=bash
#

export ai_staging_folder="${HOME}/.ai_staging"
[[ -d ${ai_staging_folder} ]] || mkdir -p "${ai_staging_folder}"

export project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd -P)"
export dest_dir="${project_root}/plugins"

export -A plugins=(
  [pstack]="git@github.com:cursor/plugins#pstack"
)

ok() {
  echo -e "\e[50G ✅ $*"
}
fail() {
  echo -e "\e[50G ❌ $*"
  exit 1
}

function install-plugin() {
  local repo=$1
  local plugin=$2

  # extract subdir and repo dir from repo
  repo=${repo%#*}
  # extract repo dir from repo
  repo_dir=${repo#*/}

  echo "Installing plugin [${plugin}] from [${plugin}] in [${repo}]"
  echo "  → checkout into ${ai_staging_folder}/${repo_dir}"

  cd ${ai_staging_folder}
  [[ -d ${repo_dir} ]] && rm -rf ${repo_dir}
  echo -n "Cloning ${repo}... "
  git clone ${repo} ${repo_dir} >/dev/null 2>&1
  [[ $? -ne 0 ]] && fail "failed to clone ${repo}"
  ok "cloned ${repo}"

  cd ${repo_dir} || fail "expected to find ${repo_dir} under ${ai_staging_folder}"

  if [[ -d ${plugin} ]]; then
    echo -ne "  → copying ${plugin} to ${dest_dir}/${plugin}"
    cp -rp ${plugin} ${project_root}/plugins/${plugin} >/dev/null 2>&1
    [[ $? -eq 0 ]] && ok "copied ${plugin}" || fail "failed to copy ${plugin}"
  fi
  cd ${project_root}
}

list-plugins() {
  for plugin in "${!plugins[@]}"; do
    repo=${plugins[$plugin]}
    echo -e "  ${plugin} → ${repo}"
  done
}

main() {
  echo "Installing plugins into [${dest_dir}]"
  for plugin in "${!plugins[@]}"; do
    repo=${plugins[$plugin]}
    install-plugin "${repo}" "${plugin}"
  done
}

if [[ $* =~ "-h" || $* =~ "--help" ]]; then
  echo "Usage:"
  echo -e "  $(basename $0)\n"
  echo "Description:"
  echo "  Installs potentially multiple plugins from GitHub repositories."
  echo -e "  Supports sub-directories within repositories.\n"
  echo "Plugins:"
  list-plugins
  exit 0
else
  main "$@"
fi

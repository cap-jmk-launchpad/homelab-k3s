grep -q pull_policy /etc/gitlab-runner/config.toml || sed -i '/allowed_pull_policies/a\    pull_policy = "if-not-present"' /etc/gitlab-runner/config.toml
grep -E 'pull_policy|allowed_pull' /etc/gitlab-runner/config.toml

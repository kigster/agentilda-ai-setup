## Claude Plugins

On any new system, ensure that the following plugins are installed:

```bash
# Marketplaces
claude plugin marketplace add st0012/ruby-skills
claude plugin marketplace add hoblin/claude-ruby-marketplace
claude plugin marketplace add ahmedasmar/devops-claude-skills

# Ruby/Rails (install immediately)
claude plugin install ruby-skills@ruby-skills
claude plugin install ruby-lsp@ruby-skills
claude plugin install rspec@claude-ruby-marketplace
claude plugin install activerecord@claude-ruby-marketplace
claude plugin install rspec@claude-ruby-marketplace

# Frontend
npx claude-plugins install @anthropics/claude-code-plugins/frontend-design

# Quality
npx claude-plugins install @anthropics/claude-code-plugins/pr-review-toolkit
npx claude-plugins install @anthropics/claude-code-plugins/security-guidance

# DevOps (when you're ready to deploy, not before)
claude plugin install iac-terraform@devops-skills
claude plugin install ci-cd@devops-skills

claude plugin marketplace add motlin/claude-code-plugins 
claude plugin install justfile@motlin-claude-code-plugins
```

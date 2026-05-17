# aliases
alias cl=clear
alias vim=nvim
alias code=vscodium
alias kctx="kubie ctx"
alias kns="kubie ns"
if ! command -v batcat &> /dev/null
    alias cat=bat
else
    alias cat=batcat
end

# ECR login — set AWS_ECR_ACCOUNT and AWS_ECR_REGION in your environment
alias ecrlogin="aws ecr get-login-password --region \$AWS_ECR_REGION | docker login --username AWS --password-stdin \$AWS_ECR_ACCOUNT.dkr.ecr.\$AWS_ECR_REGION.amazonaws.com"

set -g theme_display_date no

source $HOME/.asdf/asdf.fish

starship init fish | source
fastfetch

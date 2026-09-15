# Morse Micro work environment — non-secret. Real credentials live in ~/.zshenv.secrets
# (see zsh/zshenv.secrets.template), sourced separately by zsh/zshenv.
# Only installed with `install.sh --with-work`.

export STM32_PRG_PATH="$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"

### TestRail
export TESTRAIL_URL="https://morsetest.testrail.io/"
export TESTRAIL_USERNAME="zsh-config@users.noreply.github.com"

### Atlassian
export ATLASSIAN_LOGIN="zsh-config@users.noreply.github.com"

### New Relic
export NEW_RELIC_ACCOUNT_ID="4088222"
export NEW_RELIC_PIBOOT_ID="NDA4ODIyMnxJTkZSQXxOQXw0Njg1MzE3NTc5OTY2NDczODcy"

### Jenkins
export JENKINS_URL="https://beach.sydney.mm.lcl"
export JENKINS_USR="zsh-config@users.noreply.github.com"
export JENKINS_DEV_URL="https://beach-dev.sydney.mm.lcl"

export PYTHONHTTPSVERIFY="0"

### DB
export DB_SCHEMA="svt"
export DB_SERVER="morse-data.che3yld3w1kr.ap-southeast-2.rds.amazonaws.com:3306"
export SVT_DB="$DB_SERVER/$DB_SCHEMA"
export SVT_USR="svt_prod_read_only"

export NODE_EXTRA_CA_CERTS="$HOME/.config/claude-jenkins-dev-ca.pem"

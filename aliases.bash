# Start / Stop stack docker
alias forge:start='cd $HOME/php-devforge-config && docker-compose up -d && cd -'
alias forge:stop='cd $HOME/php-devforge-config && docker-compose stop && cd -'

#Switch PHP version and reload configuration
alias forge:current='sed -ne "s/^PHP_VERSION=\([0-9]*\)$/Running version php\1/p" $HOME//configs-docker/.env'
alias forge:reload='cd $HOME/php-devforge-config && docker-compose up -d && docker-compose up -d && cd -'
alias forge:use:php83='cd $HOME/php-devforge-config && sed -i "s/PHP_VERSION=.*/PHP_VERSION=83/g" .env && docker-compose up -d && cd -'
alias forge:use:php84='cd $HOME/php-devforge-config && sed -i "s/PHP_VERSION=.*/PHP_VERSION=84/g" .env && docker-compose up -d && cd -'

#Go into PHP container
alias forge:exec:php83='docker exec -it -w $(if pwd|grep 'public_html' > /dev/null; then pwd; else echo '/home/php-devforge'; fi) -u php-devforge php83dev bash'
alias forge:exec:php84='docker exec -it -w $(if pwd|grep 'public_html' > /dev/null; then pwd; else echo '/home/php-devforge'; fi) -u php-devforge php84dev bash'

# Log PHP
alias forge:logs:php83='docker logs -f php83dev'
alias forge:logs:php84='docker logs -f php84dev'
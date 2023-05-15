read -p "Enter username : " _user
read -p "Enter password : " _pass

echo $(htpasswd -nb $_user $_pass) | sed -e s/\\$/\\$\\$/g


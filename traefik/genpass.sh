#!/bin/bash
read -p "Enter username: " _user
read -p "Enter password: " _pass

hashed=$(openssl passwd -apr1 "$_pass" | sed 's/\$/\$/g')

echo "$hashed" | xclip -selection clipboard

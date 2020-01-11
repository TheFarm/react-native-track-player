#!/bin/sh

sed -n -e '/path/,/url/p' .gitmodules | sed 'N;s/\n/\$$$/' |
while IFS= read -r line; do 
  if [[ $line =~ (.*)\$\$\$(.*) ]] ; then 
    path=$(echo ${BASH_REMATCH[1]} | sed 's/.*= //')
    url=$(echo ${BASH_REMATCH[2]} | sed 's/.*= //')

    if [ "$(ls -A ${path})" ] ; then 
      echo "Folder ${path} seems to exist, removing the folder"
      rm -rf $path
    fi 
      
    echo "Folder ${path} doesn't exist, performing git clone"
    git clone $url $path
  fi 
done

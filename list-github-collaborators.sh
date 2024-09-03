#!/bin/bash
#
#This script will list the collaborators of a particular repository who is not an admin
#
#
# GitHub API URL
API_URL="https://api.github.com"

#GitHub username and personal access token
USERNAME=$username
TOKEN=$token

#User and Repository information
REPO_OWNER=$1
REPO_NAME=$2

#Function to make a GET request to the GitHub API
function github_api_get {
        local endpoint="$1"
        local url="${API_URL}/${endpoint}"

        #Send a GET request to the GitHub API with authentication
        curl -s -u "${USERNAME}:${TOKEN}" "$url"
}

#Function to list all the collaborators of the repository and the role is not admin
function list_users_with_read_access {
        local endpoint="repos/${REPO_OWNER}/${REPO_NAME}/collaborators"

        #Fetch the names of the collaborators whose role is not admin
        collaborators="$(github_api_get "$endpoint" | jq -r '.[] | select(.permissions.admin == false) | .login')"

        #Display the list of collaborators
        if [[ -z "$collaborators" ]]; then
                echo "No users"
        else
                echo "$collaborators"
        fi
}

#Main Script
list_users_with_read_access

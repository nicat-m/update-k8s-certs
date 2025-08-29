#!/bin/bash


#******************************************** GLOBAL VARIABLES *************************************************

current_day=`date +%d-%m-%Y-%T`
SSH_USER=ansible
USER_HOME=/home/ansible
WORKDIR=/home/ansible/scripts
CONFIG_FOLDER=$WORKDIR/config

################### FOR GITLAB VARIABLES ###################

GITLAB_TOKEN=`cat $WORKDIR/gitlab_token.txt`         ## bu variable gitlab_token.txt file-da tanidilacaq ordan oxumasi ucun
USER_ID=352                                 ## user id
DOMAIN=gitlab.local
GITLAB_PAT_URL=https://$DOMAIN/api/v4/users/$USER_ID/personal_access_tokens
GITLAB_RES_URL=https://$DOMAIN/api/v4/personal_access_tokens

#**************************************************************************************************************




# Kubernetes sertifikatin yenilenmesi ucun yazilan funksiya...

renew_certs(){

    echo ""
    echo "CLUSTER_NAME: $CLUSTER_NAME"
    echo ""
    echo "HOSTNAME: $HOSTNAME"
    echo ""

    if [ $certs_current_date -le 10 ] || [ "$certs_current_date" = "<invali" ]
    then

        for nodes in $MASTER_NODES
        do
            echo ""
            ssh $SSH_USER@$nodes -t sudo /usr/local/bin/kubeadm certs renew all

            if [ $? -ne 0 ]; then
                echo "$current_day Error renewing certs on $nodes"
                exit 1
            fi

            echo ""
            Message="$current_day : $CLUSTER_NAME K8s certs renew successfully for this nodes:  $nodes"
            echo $Message
            echo ""
            ssh $SSH_USER@$nodes -t sudo ls -l $KUBECONFIG_PATH
            echo ""

            echo "$current_day Changing config file for root user"
            echo ""
            ssh $SSH_USER@$nodes -t sudo rm -rf $ROOT_KUBECONFIG_PATH
            ssh $SSH_USER@$nodes -t sudo cp -pr $KUBECONFIG_PATH $ROOT_KUBECONFIG_PATH
            echo ""
            echo "$current_day Config file updated for root user !!!"
            echo ""

            slack_notif

        done

            check_and_fix_configfile                    ## kubeconfig file yoxlayan funksiya cagrilir
            update_gitlab_variable                      ## variable update edilmesi ucun funksiya

    else
            echo ""
            echo "$current_day : K8s certs not expired !!!"
            echo ""
            echo "Expire after $certs_current_date days"
            echo ""

            check_gitlab_token                          ## gitlab token yoxlayan funksiya
    fi
}


# kubeconfig file daxilinde server hissesinin yoxlanilmasi ucun funksiya

check_and_fix_configfile(){

    if [[ $CONFIG_SERVER_HOST == "$HA_IP" ]]
    then

            echo ""
            echo "$current_day $ROOT_KUBECONFIG_PATH is okay !!!"
            echo ""
	    ssh $SSH_USER@$MASTER_IP -t sudo cp -pr $ROOT_KUBECONFIG_PATH $USER_HOME/$CLUSTER_NAME
            ssh $SSH_USER@$MASTER_IP -t sudo chown $SSH_USER:$SSH_USER $USER_HOME/$CLUSTER_NAME
            scp $SSH_USER@$MASTER_IP:$USER_HOME/$CLUSTER_NAME $CONFIG_FOLDER/$CLUSTER_NAME
	    echo ""

    else

            echo ""
            echo "$current_day Config file is wrong server ip address: $CONFIG_SERVER_HOST"
            echo ""
            ssh $SSH_USER@$MASTER_IP -t sudo cp -pr $ROOT_KUBECONFIG_PATH $USER_HOME/$CLUSTER_NAME
            ssh $SSH_USER@$MASTER_IP -t sudo chown $SSH_USER:$SSH_USER $USER_HOME/$CLUSTER_NAME
            scp $SSH_USER@$MASTER_IP:$USER_HOME/$CLUSTER_NAME $CONFIG_FOLDER/$CLUSTER_NAME
            sudo sed -i "s/$CONFIG_SERVER_HOST:$CONFIG_SERVER_PORT/$HA_IP:$HA_PORT/g" $CONFIG_FOLDER/$CLUSTER_NAME
            Message="$current_day $CLUSTER_NAME file updated !!!"
            echo $Message
            echo ""
            cat $CONFIG_FOLDER/$CLUSTER_NAME |grep server
            echo ""

            slack_notif

    fi
}

# Gitlab token check edilmesi...

check_gitlab_token(){

     ### VARIABLES

    response=$(curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_RES_URL?user_id=$USER_ID" \
                -s -w "%{http_code}" -o response.json)
    current_date=`date +%s`
    GENERATE_DATE=`date +%F`
    TOKEN_NAME=renew-certs-on-k8s-$GENERATE_DATE


    if [ "$response" -eq 200 ]
    then
        echo ""
        echo "Success to retrieve data from Gitlab, HTTP status code: $response"
        echo ""

        expires_at=`curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_RES_URL?user_id=$USER_ID" | \
                jq 'sort_by(.created_at) | last | .expires_at' | \
                awk '{print $1}' | tr -d '"'`
        expires_date=$(date -d "$expires_at" +%s)
        diff_days=$(( (expires_date - current_date) / 86400 ))

        if [ $diff_days -le 10 ]
        then

            echo ""
            echo "$current_day  Token expire after 5 days"
            echo ""
            Message="$current_day  New token created successfully !!!"
            echo $Message
            echo ""
            NEW_TOKEN=`curl -s --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                --header "Content-Type: application/json" \
                --data '{"name": "'"$TOKEN_NAME"'","scopes": ["api"]}' \
                "$GITLAB_PAT_URL" | \
                jq . |grep token |awk '{print $2}' |tr -d '"'`

            echo $NEW_TOKEN > gitlab_token.txt

            slack_notif

        else
            echo ""
            echo "$current_day  Gitlab token is not exipred. Expiring date is: $expires_at"
            echo ""

        fi

    else
        echo "Failed to retrieve data from Gitlab, HTTP status code: $response"
    fi

}


# Gitlab-da olan variable update olunmasi ucun funksiya

update_gitlab_variable(){

    GITLAB_API_URL=https://$DOMAIN/api/v4/groups/$GROUP_ID/variables
    KUBECONFIG_CONTENT=$(cat $CONFIG_FOLDER/$CLUSTER_NAME | jq -Rs .)

    check_gitlab_token # burada gitlab token yoxlayan funksiya cagrilir

    if [ "$response" -eq 200 ]
    then
        echo ""
        echo "Success to retrieve data from Gitlab, HTTP status code: $response"
        echo ""

        curl --request PUT --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
             --header "Content-Type: application/json" \
             --data '{"value": '"$KUBECONFIG_CONTENT"'}' \
             "$GITLAB_API_URL/$VARIABLE_NAME"

        echo ""
        echo ""
        Message="$current_day **** $VARIABLE_NAME **** this variable updated in Gitlab: Group_name is $GROUP_NAME !!!"
        echo $Message
        echo ""

        slack_notif

    else
        echo "Failed to retrieve data from Gitlab, HTTP status code: $response"
    fi

}

# Slack notification gonderilmesi ucun funksiya

slack_notif(){

    SLACK_WEBHOOK_URL="webhook_url"

    curl -X POST -H 'Content-type: application/json' --data '{"text": "'"$Message"'"}' $SLACK_WEBHOOK_URL

}

# Bu funksiya ile avis2,eportal ve avisproxy (dev,prep,prod) eyni anda yoxlamasi ucundu.
# Script elimden geldiyi qeder dinamik etmeye calismisam :))

k8s_clusters(){

    MASTER_IP=$1
    CLUSTER_NAME=$2
    HA_IP=$3
    HA_PORT=$4
    GROUP_ID=$5
    VARIABLE_NAME=$6
    GROUP_NAME=$7
    MASTER_NODES=`cat $WORKDIR/hosts.txt |grep $8 | awk '{print $1}'`

    remote_server=$(ssh -T $SSH_USER@$MASTER_IP << 'EOF'

        certs_current_date=$(sudo /usr/local/bin/kubeadm certs check-expiration 2>&1 | grep admin | awk '{print $7}' | cut -d d -f1)
        KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
        ROOT_KUBECONFIG_PATH="/root/.kube/config"
        CONFIG_SERVER_HOST=$(sudo cat $ROOT_KUBECONFIG_PATH | grep server | cut -d / -f3 | cut -d : -f1)
        CONFIG_SERVER_PORT=$(sudo cat $ROOT_KUBECONFIG_PATH | grep server | cut -d / -f3 | cut -d : -f2)
        HOSTNAME=`hostname`

        echo "certs_current_date=$certs_current_date"
        echo "KUBECONFIG_PATH=$KUBECONFIG_PATH"
        echo "ROOT_KUBECONFIG_PATH=$ROOT_KUBECONFIG_PATH"
        echo "CONFIG_SERVER_HOST=$CONFIG_SERVER_HOST"
        echo "CONFIG_SERVER_PORT=$CONFIG_SERVER_PORT"
        echo "HOSTNAME"=$HOSTNAME


EOF
)

while IFS= read -r line; do
    if [[ "$line" == *=* ]]; then
        export "$line"
    fi
done <<< "$remote_server"

renew_certs

echo "=========================================================================================================="

}

# 1. master-1-ip
# 2. Cluster-name
# 3. HA-IP
# 4. HA-PORT
# 5. Gitlab-GROUP-ID
# 6. Gitlab-Variable-name
# 7. Gitlab-Group-name
# 8. name for filter in hosts.txt file


# develop
k8s_clusters "master_ip" "cluster_name" "LB_ip" "6443" "group_id" "gitlab_var_name" "group_name" "develop"

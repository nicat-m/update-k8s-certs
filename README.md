# update-k8s-certs

## Getting started

1. Clone repository
2. Write all master ip in "hosts.txt" file for each env
3. Run the script or add to schedule


```
git clone https://github.com/nicat-m/update-k8s-certs.git
cd update-k8s-certs
vim hosts.txt
write hosts in this file
vim gitlab_token.txt
write your token in this file


vim update-k8s-certs

in below of script write like this for each env 

1. first is function name when run script this funtion calling 
2. second one is your master ip address if you have 3 master or more it need write one of these
3. third is cluster name what you want to write
4. if you have HA or loadbalancer for master ip you should write ha ip in this section
5. HA port or master kube_api port
6. Gitlab group id
7. Kube config variable name which is use in giltab pipeline
8. Gitlab group name
9. this name which is you write in hosts.txt file

k8s_clusters "10.0.0.10" "PROD-CLUSTER" "10.0.0.30" "8383" "129" "PROD_KUBE_CONFIG" "e-services" "prod-master-01"

After this create ssh user for your env and need to give access for this user connection all env

## Run this command after doing everything
chmod u+x update-k8s-certs.sh
./update-k8s-certs.sh
```

```
Hosts txt file content example:

10.0.0.10 prod
10.0.0.50 dev
```

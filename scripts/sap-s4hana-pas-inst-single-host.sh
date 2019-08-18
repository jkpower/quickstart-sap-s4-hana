#!/bin/bash -x

###Global Variables###
source /root/install/config.sh
TZ_LOCAL_FILE="/etc/localtime"
NTP_CONF_FILE="/etc/ntp.conf"
OS_VER="/etc/os-release"
USR_SAP="/usr/sap"
SAPMNT="/sapmnt"
USR_SAP_VOLUME="/dev/xvdb"
SAPMNT_VOLUME="/dev/xvdc"
SWAP_DEVICE="/dev/xvdd"
FSTAB_FILE="/etc/fstab"
DHCP="/etc/sysconfig/network/dhcp"
CLOUD_CFG="/etc/cloud/cloud.cfg"
NETCONFIG="/etc/sysconfig/network/config"
IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4/)
HOSTS_FILE="/etc/hosts"
HOSTNAME_FILE="/etc/HOSTNAME"
INSTANCE_TYPE=$(curl http://169.254.169.254/latest/meta-data/instance-type 2> /dev/null)
ETC_SVCS="/etc/services"
SAPMNT_SVCS="/sapmnt/SWPM/services"
SW_TARGET="/sapmnt/SWPM"
SRC_INI_DIR="/root/install"

ASCS_DONE="/sapmnt/SWPM/ASCS_DONE"
PAS_DONE="/sapmnt/SWPM/PAS_DONE"
MASTER_HOSTS="/sapmnt/SWPM/master_etc_hosts"
SAPINST="/sapmnt/SWPM/sapinst"
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document/ | grep -i region | awk '{ print $3 }' | sed 's/"//g' | sed 's/,//g')

ASCS_INI_FILE="/sapmnt/SWPM/s4-ascs.params"
PAS_INI_FILE="/sapmnt/SWPM/s4-pas.params"
DB_INI_FILE="/sapmnt/SWPM/s4-db.params"
AAS_INI_FILE="/sapmnt/SWPM/s4-aas.params"

ASCS_PRODUCT="NW_ABAP_ASCS:S4HANA1809.CORE.HDB.ABAP"
DB_PRODUCT="NW_ABAP_DB:S4HANA1809.CORE.HDB.ABAP"
PAS_PRODUCT="NW_ABAP_CI:S4HANA1809.CORE.HDB.ABAP"

HOSTNAME=$(hostname)

set_install_jq () {
#install jq s/w
    cd /tmp
	wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
    mv jq-linux64 jq
    chmod 755 jq
}

set_tz() {
#set correct timezone per CF parameter input
    rm "$TZ_LOCAL_FILE"

    case "$TZ_INPUT_PARAM" in
    PT)
        TZ_ZONE_FILE="/usr/share/zoneinfo/US/Pacific"
        ;;
    CT)
        TZ_ZONE_FILE="/usr/share/zoneinfo/US/Central"
        ;;
    ET)
        TZ_ZONE_FILE="/usr/share/zoneinfo/US/Eastern"
        ;;
    *)
        TZ_ZONE_FILE="/usr/share/zoneinfo/UTC"
        ;;
    esac

    ln -s "$TZ_ZONE_FILE" "$TZ_LOCAL_FILE"

    #validate correct timezone
    CURRENT_TZ=$(date +%Z | cut -c 1,3)

    if [ "$CURRENT_TZ" == "$TZ_INPUT_PARAM" -o "$CURRENT_TZ" == "UC" ]
    then
        echo 0
    else
        echo 1
    fi
}

set_install_ssm() {
	cd /tmp
	wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
	rpm -ivh /tmp/amazon-ssm-agent.rpm
	echo '#!/usr/bin/sh' > /etc/init.d/ssm
	echo "service amazon-ssm-agent start" >> /etc/init.d/ssm
	chmod 755 /etc/init.d/ssm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
}

set_dbinifile() {
#set the vname of the database server in the INI file
    #set the db server hostname
    sed -i  "/NW_HDB_getDBInfo.dbhost/ c\NW_HDB_getDBInfo.dbhost = ${DBHOSTNAME}" $DB_INI_FILE
        
    #set the password from the SSM parameter store
    sed -i  "/NW_HDB_getDBInfo.systemPassword/ c\NW_HDB_getDBInfo.systemPassword = ${MP}" $DB_INI_FILE
    sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $DB_INI_FILE
    sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $DB_INI_FILE
    sed -i  "/NW_HDB_DB.abapSchemaPassword/ c\NW_HDB_DB.abapSchemaPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_Recovery_Install_HDB.sidAdmPassword/ c\NW_Recovery_Install_HDB.sidAdmPassword = ${MP}" $DB_INI_FILE

    #set the SID and Schema
    sed -i  "/NW_HDB_getDBInfo.dbsid/ c\NW_HDB_getDBInfo.dbsid = ${SAP_SID}" $DB_INI_FILE
    sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $DB_INI_FILE
    sed -i  "/NW_HDB_DB.abapSchemaName/ c\NW_HDB_DB.abapSchemaName = ${SAP_SCHEMA_NAME}" $DB_INI_FILE
    sed -i  "/NW_Recovery_Install_HDB.sidAdmName/ c\NW_Recovery_Install_HDB.sidAdmName = ${SIDADM}" $DB_INI_FILE
    sed -i  "/NW_HDB_getDBInfo.instanceNumber/ c\NW_HDB_getDBInfo.instanceNumber = ${SAPInstanceNum}" $DB_INI_FILE
    sed -i  "/storageBasedCopy.hdb.instanceNumber/ c\storageBasedCopy.hdb.instanceNumber = ${SAPInstanceNum}" $DB_INI_FILE
       
    #set the UID and GID
    sed -i  "/nwUsers.sidAdmUID/ c\nwUsers.sidAdmUID = ${SIDadmUID}" $DB_INI_FILE
    sed -i  "/nwUsers.sapsysGID/ c\nwUsers.sapsysGID = ${SAPsysGID}" $DB_INI_FILE
   
    #Set software locations
    sed -i  "/archives.downloadBasket/ c\archives.downloadBasket = ${SW_TARGET}/s4-1809" $DB_INI_FILE
    sed -i  "/NW_Recovery_Install_HDB.extractLocation/ c\NW_Recovery_Install_HDB.extractLocation = /backup/data/${SAP_SID}" $DB_INI_FILE
}

set_ascsinifile() {
#set the vname of the ascs server in the INI file
    sed -i  "/NW_SCS_Instance.scsVirtual/ c\NW_SCS_Instance.scsVirtualHostname = ${HOSTNAME}" $ASCS_INI_FILE
    sed -i  "/NW_SCS_Instance.instanceNumber/ c\NW_SCS_Instance.instanceNumber = ${SAPInstanceNum}" $ASCS_INI_FILE
    sed -i  "/nwUsers.sidadmPasswod/ c\nwUsers.sidadmPassword = ${MP}" $ASCS_INI_FILE
    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $ASCS_INI_FILE
    sed -i  "/hostAgent.sapAdmPassword/ c\hostAgent.sapAdmPassword = ${MP}" $ASCS_INI_FILE

    #set the SID
    sed -i  "/NW_GetSidNoProfiles.sid/ c\NW_GetSidNoProfiles.sid = ${SAP_SID}" $ASCS_INI_FILE

    #set the UID and GID
    sed -i  "/nwUsers.sidAdmUID/ c\nwUsers.sidAdmUID = ${SIDadmUID}" $ASCS_INI_FILE
    sed -i  "/nwUsers.sapsysGID/ c\nwUsers.sapsysGID = ${SAPsysGID}" $ASCS_INI_FILE
 
    # Add - These 2 are set in S4/HANA ascs.params file
    sed -i  "/archives.downloadBasket/ c\archives.downloadBasket = ${SW_TARGET}/s4-1809" $ASCS_INI_FILE
    sed -i  "/NW_getFQDN.FQDN/ c\NW_getFQDN.FQDN = ${HOSTED_ZONE}" $ASCS_INI_FILE
}


set_pasinifile() {
#set the vname of the database server in the INI file
    #set the password from the SSM parameter store
    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $PAS_INI_FILE
    sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/storageBasedCopy.abapSchemaPassword/ c\storageBasedCopy.abapSchemaPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/nwUsers.sidadmPasswod/ c\nwUsers.sidadmPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/hostAgent.sapAdmPassword/ c\hostAgent.sapAdmPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/NW_HDB_DB.abapSchemaPassword/ c\NW_HDB_DB.abapSchemaPassword = ${MP}" >> $PAS_INI_FILE

    #set the profile directory
    sed -i  "/NW_readProfileDir.profileDir/ c\NW_readProfileDir.profileDir = /sapmnt/${SAP_SID}/profile" $PAS_INI_FILE
     
    #set the SID and Schema
    sed -i  "/NW_HDB_DB.abapSchemaName/ c\NW_HDB_DB.abapSchemaName = ${SAP_SCHEMA_NAME}" >> $PAS_INI_FILE
    sed -i  "/storageBasedCopy.hdb.instanceNumber/ c\storageBasedCopy.hdb.instanceNumber = ${SAPInstanceNum}" $PAS_INI_FILE
    sed -i  "/NW_CI_Instance.ascsInstanceNumber/ c\NW_CI_Instance.ascsInstanceNumber = ${SAPInstanceNum}" $PAS_INI_FILE
    sed -i  "/NW_CI_Instance.ciInstanceNumber/ c\NW_CI_Instance.ciInstanceNumber = $(printf "%02d" $(( 10#${SAPInstanceNum} + 1 )))" $PAS_INI_FILE
    
    #set the UID and GID
    sed -i  "/nwUsers.sidAdmUID/ c\nwUsers.sidAdmUID = ${SIDadmUID}" $PAS_INI_FILE
    sed -i  "/nwUsers.sapsysGID/ c\nwUsers.sapsysGID = ${SAPsysGID}" $PAS_INI_FILE
 
    sed -i  "/archives.downloadBasket/ c\archives.downloadBasket = ${SW_TARGET}/s4-1809" $PAS_INI_FILE
    sed -i  "/NW_getFQDN.FQDN/ c\NW_getFQDN.FQDN = ${HOSTED_ZONE}" $PAS_INI_FILE
    sed -i  "/NW_CI_Instance.ciVirtualHostname/ c\NW_CI_Instance.ciVirtualHostname = ${HOSTNAME}" $PAS_INI_FILE
    sed -i  "/NW_CI_Instance.ascsVirtualHostname/ c\NW_CI_Instance.ascsVirtualHostname = ${HOSTNAME}" $PAS_INI_FILE
}

set_cleanup_inifiles() {
#cleanup the password in the  the INI files

    MP="DELETED"
    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $ASCS_INI_FILE
    sed -i  "/hostAgent.sapAdmPassword/ c\hostAgent.sapAdmPassword = ${MP}" $ASCS_INI_FILE
    sed -i  "/nwUsers.sidadmPasswod/ c\nwUsers.sidadmPassword = ${MP}" $PAS_INI_FILE

    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $PAS_INI_FILE
    sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/storageBasedCopy.abapSchemaPassword/ c\storageBasedCopy.abapSchemaPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/nwUsers.sidadmPasswod/ c\nwUsers.sidadmPassword = ${MP}" $PAS_INI_FILE
    sed -i  "/hostAgent.sapAdmPassword/ c\hostAgent.sapAdmPassword = ${MP}" $PAS_INI_FILE

    sed -i  "/NW_HDB_getDBInfo.systemPassword/ c\NW_HDB_getDBInfo.systemPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_Recovery_Install_HDB.sidAdmPassword/ c\NW_Recovery_Install_HDB.sidAdmPassword = ${MP}" $DB_INI_FILE
    sed -i  "/storageBasedCopy.hdb.systemPassword/ c\storageBasedCopy.hdb.systemPassword = ${MP}" $DB_INI_FILE
    sed -i  "/HDB_Schema_Check_Dialogs.schemaPassword/ c\HDB_Schema_Check_Dialogs.schemaPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_GetMasterPassword.masterPwd/ c\NW_GetMasterPassword.masterPwd = ${MP}" $DB_INI_FILE
    sed -i  "/NW_HDB_DB.abapSchemaPassword/ c\NW_HDB_DB.abapSchemaPassword = ${MP}" $DB_INI_FILE
    sed -i  "/NW_HDB_getDBInfo.systemDbPassword/ c\NW_HDB_getDBInfo.systemDbPassword = ${MP}" $PAS_INI_FILE
}

set_awsdataprovider() {
#install the AWS dataprovider require for AWS support
    aws s3 cp s3://aws-data-provider/bin/aws-agent_install.sh /tmp/ > /dev/null    
    if [ -f /tmp/aws-agent_install.sh ]
    then
        bash /tmp/aws-agent_install.sh > /dev/null
        echo 0
    else
        echo 1
    fi
}

set_oss_configs() {
    #This section is from OSS #2205917 - SAP HANA DB: Recommended OS settings for SLES 12 / SLES for SAP Applications 12
    #and OSS #2292711 - SAP HANA DB: Recommended OS settings for SLES 12 SP1 / SLES for SAP Applications 12 SP1 
    
    # Disable THP
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/init.d/boot.local
    
    echo 10 > /proc/sys/vm/swappiness
    echo "echo 10 > /proc/sys/vm/swappiness" >> /etc/init.d/boot.local
    # Disable KSM
    echo 0 > /sys/kernel/mm/ksm/run
    echo "echo 0 > /sys/kernel/mm/ksm/run" >> /etc/init.d/boot.local
    # Disable SELINUX
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
    sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/sysconfig/selinux
    
    if grep -i suse ${OS_VER} 1> /dev/null
    then
        # Install and configure SLES 
        zypper -n remove ulimit > /dev/null
        echo "###################" >> /etc/init.d/boot.local
        echo "#BEGIN: This section inserted by AWS SAP Quickstart" >> /etc/init.d/boot.local
        #Disable AutoNUMA
        echo 0 > /proc/sys/kernel/numa_balancing
        echo "echo 0 > /proc/sys/kernel/numa_balancing" >> /etc/init.d/boot.local
        zypper -n install gcc > /dev/null
        zypper -n install libgcc_s1 libstdc++6 > /dev/null
        echo "#END: This section inserted by AWS SAP HANA Quickstart" >> /etc/init.d/boot.local
        echo "###################" >> /etc/init.d/boot.local
        # Install GCC and GC++ compilers. GCC includes package libatomic1 that is required for all GCC 7 compiled apps, see OSS note 2593824. 
        zypper -n install gcc-c++ > /dev/null
        zypper -n install systemd > /dev/null
        zypper -n install nvme-cli > /dev/null

        if grep -i sap ${OS_VER} 1> /dev/null
        then
            # "Optional" - installing GNOME Desktop Environment
            zypper -n install -t pattern x11 gnome_basic > /dev/null 
            # --- OSS Note 1275776 -----------------
            zypper -n install saptune > /dev/null
            saptune daemon start
            saptune solution apply HANA
            saptune solution apply S4HANA-APPSERVER
            # --------------------------------------
        else
            # --- OSS Note 1275776 -----------------
            zypper -n install sapconf > /dev/null
            systemctl start sapconf.service > /dev/null
        fi
        # ---- Specifics for SLES15 ----
        if grep 15 ${OS_VER} 1> /dev/null
        then 
            zypper -n install unrar_wrapper > /dev/null
            zypper -n install net-tools-deprecated > /dev/null
        fi
        # Update all installed packages to the latest version
        zypper -n update --auto-agree-with-licenses
    else
        # RHEL package install and configuration
        # --------------------------------------------
        yum -y install vhostmd > /dev/null
        yum -y install vm-dump-metrics > /dev/null
        yum -y install glibc > /dev/null
        yum -y install gcc > /dev/null
        yum -y install gcc-c++ > /dev/null
        yum -y install compat-sap-c++ > /dev/null
        yum -y install nvme-cli > /dev/null
        yum -y update > /dev/null
    fi
}

Implement_Chrony()
{
    if grep -i suse ${OS_VER} 1> /dev/null
    then
        zypper -n remove 'ntp*' 1>/dev/null
        zypper -n install chrony 1>/dev/null
    else
        yum -y erase 'ntp*' 1>/dev/null
        yum -y install chrony 1>/dev/null
    fi
    echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
    ps -ef | grep '[c]hronyd' && service chronyd stop
    service chronyd start 1>/dev/null
    chronyc sources -v | grep '169.254.169.123' && return 0 || return 1
}

#set_ntp() {
#set ntp in the /etc/ntp.conf file
#    cp "$NTP_CONF_FILE" "$NTP_CONF_FILE.bak"
#    echo "server 0.pool.ntp.org" >> "$NTP_CONF_FILE"
#    echo "server 1.pool.ntp.org" >> "$NTP_CONF_FILE"
#    echo "server 2.pool.ntp.org" >> "$NTP_CONF_FILE"
#    echo "server 3.pool.ntp.org" >> "$NTP_CONF_FILE"
#    systemctl start ntpd
#    echo "systemctl start ntpd" >> /etc/init.d/boot.local
     
#    COUNT_NTP=$(grep ntp "$NTP_CONF_FILE" | wc -l)
#    if [ "$COUNT_NTP" -ge 4 ]
#    then
#        echo 0
#    else
#        #did not sucessfully update ntp config
#        echo 1
#    fi
#}

set_filesystems() {
#create /usr/sap filesystem and mount /sapmnt
    if [ ${INSTANCE_TYPE:1:1} == 5 ]
    then
#        for devf in `ls /dev/nvme?n? | grep -v $(df | grep boot | head -c12)`
        for devf in `ls /dev/nvme?n?`
        do
            if nvme id-ctrl -v ${devf} | grep xvdb
            then
                USR_SAP_VOLUME=${devf}
                echo "Device file for /usr/sap is ${devf}"
            elif nvme id-ctrl -v ${devf} | grep xvdc
              then
                  SAPMNT_VOLUME=${devf}
                  echo "Device file for /sapmnt is ${devf}"
              elif nvme id-ctrl -v ${devf} | grep xvdd
                then
                    SWAP_DEVICE=${devf}
                    echo "Device file for SWAP is $devf"
            fi
        done
    fi
    if [ -z "$USR_SAP_VOLUME" -o -z "$SAPMNT_VOLUME" -o -z "$SWAP_DEVICE"]
    then
        echo "Exiting, can not create /usr/sap or /sapmnt or SWAP EBS volumes" 
        #signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "Exiting, can not create /usr/sap or /sapmnt or SWAP EBS volumes"
        set_cleanup_inifiles
        exit 1
    else
        mkdir $USR_SAP > /dev/null
        mkdir $SAPMNT > /dev/null
        mkdir $SW > /dev/null
    fi
    mkfs.xfs $USR_SAP_VOLUME -L USR-SAP> /dev/null
    mkfs.xfs $SAPMNT_VOLUME -L SAPMNT > /dev/null
    mkswap -L SWAP $SWAP_DEVICE > /dev/null 2>&1
    swapon $SWAP_DEVICE > /dev/null 2>&1
  
    #create /etc/fstab entries
    echo "/dev/disk/by-label/USR-SAP  $USR_SAP xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE
    echo "/dev/disk/by-label/SAPMNT   $SAPMNT  xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE
    echo "/dev/disk/by-label/SWAP	swap swap defaults 0 0" >> $FSTAB_FILE 2>&1
    mount -a > /dev/null

    #validate /usr/sap and /sapmnt filesystems were created and mounted
#    FS_USR_SAP=$(df -h | grep "$USR_SAP" | awk '{ print $NF }')
#    FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')
#    FS_USR_SAP=$(df $USR_SAP)
#    FS_SAPMNT=$(df $SAPMNT)
#    if [ -z "$FS_USR_SAP" -o -z "$FS_SAPMNT" ]
    if df | grep usr/sap > /dev/null && df | grep sapmnt > /dev/null
    then
       #we did not successfully created the filesystems and mount points	
       echo 1
    else
        #we did successfully created the filesystems and mount points	
	    echo 0
    fi
}

set_EFS() {
#mount up the EFS filesystem
	mkdir  $SAPMNT > /dev/null
    #Check if EFS is in use, if EFS is in use then we mount up from the EFS share
	if [ "$EFS" == "Yes" ]
	then
	    #create /usr/sap and swap space
        [[ ${INSTANCE_TYPE:1:1} == 5 ]] && { USR_SAP_VOLUME=/dev/nvme1n1 && SWAP_DEVICE=/dev/nvme3n1; } || { USR_SAP_VOLUME=/dev/xvdb && SWAP_DEVICE=/dev/xvdd; }
	    if [ -z "$USR_SAP_VOLUME" -o -z "$SWAP_DEVICE" ]
	    then
	        echo "Exiting, can not create /usr/sap or SWAP EBS volume" 
	        #signal the waithandler, 1=Failed
	        /root/install/signalFinalStatus.sh 1 "Exiting, can not create /usr/sap or SWAP EBS volume"
	        set_cleanup_inifiles
	        exit 1
	    else
	        mkdir $USR_SAP > /dev/null
	        mkfs.xfs $USR_SAP_VOLUME -L USR-SAP> /dev/null
	        mkswap -L SWAP $SWAP_DEVICE > /dev/null 2>&1
	        swapon $SWAP_DEVICE > /dev/null 2>&1
	        
	        #create /etc/fstab entries
            echo "/dev/disk/by-label/USR-SAP  $USR_SAP xfs nobarrier,noatime,nodiratime,logbsize=256k 0 0" >> $FSTAB_FILE
	        echo "/dev/disk/by-label/SWAP	swap swap defaults 0 0" >> $FSTAB_FILE 2>&1
	        mount -a
	    fi
		#mount up EFS
        echo "Mounting up EFS from this EFS location: "
        #construct the EFS DNS name
        EFS_MP=""$EFS_MT".efs."$REGION".amazonaws.com:/ "
        echo ""$EFS_MP"  "$SAPMNT"  nfs nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0"  >> $FSTAB_FILE
        #try to mount /sapmnt 3 times 
        mount /sapmnt > /dev/null
        sleep 5
        #validate /sapmnt filesystems were created and mounted
        FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')
        if [ -z "$FS_SAPMNT" ]
        then
            mount /sapmnt > /dev/null
            sleep 15
        fi

       #validate /usr/sap and /sapmnt filesystems were created and mounted
        FS_USR_SAP=$(df -h | grep "$USR_SAP" | awk '{ print $NF }')
        FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')

        if [ -z "$FS_USR_SAP" -o -z "$FS_SAPMNT" ]
        then
            mount /sapmnt > /dev/null
            sleep 60
        fi
    fi

    #validate /sapmnt filesystems were created and mounted
    FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')
    if [ -z "$FS_SAPMNT" ]
    then
	    #we did not successfully created the filesystems and mount points	
	    echo 1
    else
	    #we did successfully created the filesystems and mount points
        #we now share it out, call teh set_nfsexport function
        echo 0
    fi
}

set_s3_download() {
#download the s/w
    #download the media from the S3 bucket provided
    S3_DL=$(aws s3 sync "s3://${S3_BUCKET}/${S3_BUCKET_KP}" "$SW_TARGET" 2>&1 >/dev/null | grep "download failed")
    if [ -n "$S3_DL" ]
    then
        #download failed for some reason, try to download again
        S3_DL2=$(aws s3 sync "s3://${S3_BUCKET}/${S3_BUCKET_KP}" "$SW_TARGET" 2>&1 >/dev/null | grep "download failed")
        
        if [ -n "$S3_DL2" ]
        then
            #download failed on 2nd try, exit
            echo 1
            return
        fi
    fi
    cd "$SRC_INI_DIR" 
    cp *.params  "$SW_TARGET"
    if [ -d "$SAPINST" ]
    then
        chmod -R 755 $SW_TARGET > /dev/null 
	    cd "$SRC_INI_DIR" 
        cp *.params  "$SW_TARGET"
        echo 0
    else
	    #retry the download again
        aws s3 sync "s3://${S3_BUCKET}/${S3_BUCKET_KP}" "$SW_TARGET" > /dev/null
        #aws s3 sync "$S3_BUCKET/$S3_BUCKET_KP" "$SW_TARGET" > /dev/null
        if [ -d "$SAPINST" ]
        then
            chmod -R 755 $SW_TARGET > /dev/null 
	        cd "$SRC_INI_DIR" 
            cp *.params  "$SW_TARGET"
            echo 0
        else
            echo 1
        fi
    fi
}

set_save_services_file() {
#save the /etc/services file from the ASCS instance for other instances
    grep -i sap "$ETC_SVCS" > "$SAPMNT_SVCS"
    #need to check if services files exists
    if [ -s "$SAPMNT_SVCS" ]
    then
        echo 0
    else
        echo 1
    fi
}

set_dhcp() {
    if grep -i rhel ${OS_VER} 1> /dev/null
    then
        sed -i '/HOSTNAME/ c\HOSTNAME='$(hostname) /etc/sysconfig/network
        echo 0
    else
        sed -i '/DHCLIENT_SET_HOSTNAME/ c\DHCLIENT_SET_HOSTNAME="no"' $DHCP
        #restart network
        service network restart
        #validate dhcp file is correct
        _DHCP=$(grep DHCLIENT_SET_HOSTNAME $DHCP | grep no)
        if [ "$_DHCP" ]
        then
            echo 0
        else
            #did not sucessfully create
            echo 1
        fi
    fi
}

set_net() {
#query the R53 private hosted zone for our hostname based on our I.P. Address
    if grep -i suse ${OS_VER} 1> /dev/null
    then
        #update DNS search order with our DNS Domain name
        sed -i "/NETCONFIG_DNS_STATIC_SEARCHLIST=""/ c\NETCONFIG_DNS_STATIC_SEARCHLIST="${HOSTED_ZONE}"" $NETCONFIG
        #update the /etc/resolv.conf file
        netconfig update -f
    else
        echo "search ${HOSTED_ZONE}" >> /etc/resolv.conf
    fi
}

set_hostname() {
#set and preserve the hostname
	hostname $HOSTNAME
	#update /etc/hosts file
	echo "$IP  $HOSTNAME" >> $HOSTS_FILE
	echo "$DBIP  $DBHOSTNAME" >> $HOSTS_FILE
	#save our HOSTNAME to the master_etc_hosts file as well
	echo "$IP  $HOSTNAME  #PAS Server#" >> $MASTER_HOSTS
	echo "$HOSTNAME" > $HOSTNAME_FILE
	sed -i '/preserve_hostname/ c\preserve_hostname: true' $CLOUD_CFG
	#disable dhcp
	_DISABLE_DHCP=$(set_dhcp)
	#validate hostname and dhcp
	if [ "$(hostname)" == "$HOSTNAME" -a "$_DISABLE_DHCP" == 0 ]
	then
        echo 0
	else
		echo 1
	fi
}

set_nfsexport() {
#export the /sapmnt filesystem
    #need to check if /sapmnt filesystem files exists
    FS_SAPMNT=$(df -h | grep "$SAPMNT" | awk '{ print $NF }')
    if [ "$FS_SAPMNT" ]
    then
        #EXPORTS=$(echo $HOSTNAME | cut -c1-3)
	    #echo "$SAPMNT     $EXPORTS*(rw,no_root_squash,no_subtree_check)" >> /etc/exports
	    echo "$SAPMNT      *(rw,no_root_squash,no_subtree_check)" >> /etc/exports
        chkconfig nfs on
        if grep -i suse ${OS_VER} 1> /dev/null 
        then
            service nfsserver start
            echo "service nfsserver start" >> /etc/init.d/boot.local
        else
            service nfs start
            echo "service nfs start" >> /etc/init.d/boot.local
        fi
        sleep 15
        exportfs -a
	    echo 0
    else
        #did not sucessfully export
        echo 1
    fi
}

set_uuidd() {
#Install the uuidd daemon per SAP Note 1391070
    if grep -i suse ${OS_VER} 1>/dev/null
    then
        zypper -n install uuidd > /dev/null
    else
        yum -y install uuidd > /dev/null
    fi
    #validate the Install was successful
    _UUIDD=$(rpm -qa | grep uuidd)
    if [ "$_UUIDD" ]
    then
        echo 0
    else
        echo 1
    fi
}

set_update_cli() 
{
#update the aws cli
#    zypper -n install python-pip
#    pip install --upgrade --user awscli
    curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "/tmp/awscli-bundle.zip" 1> /dev/null
    unzip /tmp/awscli-bundle.zip -d /tmp 1> /dev/null
    /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws 1> /dev/null
}

set_SUSE_BYOS() {
    #Check to see if BYOS SLES registration is successful
    if [[ "$MyOS" =~ BYOS ]];
    then
        SUSEConnect -r "$SLESBYOSRegCode" > /dev/null
        sleep 5
        CheckSLESRegistration=$(SUSEConnect -s | grep ACTIVE)
        if [ -n "$CheckSLESRegistration" ]
        then
            SUSEConnect -p sle-module-public-cloud/12/x86_64 > /dev/null
            echo 0
        else
            echo 1
        fi
    fi
}

###Main Body###

if [ -f "/etc/sap-app-quickstart" ]
then
    echo "****************************************************************"
	echo "****************************************************************"
    echo "The /etc/sap-app-quickstart file exists, exiting the Quick Start"
    echo "****************************************************************"
    echo "****************************************************************"
    exit 0
fi

echo "----- Entering sap-s4hana-pas-inst-single-host.sh -----"

# -------------------------------------------------------------------------- #
# Temporary fix for the issue of unable to access SuSE repo issue - 07/06/19
# -------------------------------------------------------------------------- #
if grep -i suse ${OS_VER} 1> /dev/null
then
    if ls -l /etc/products.d/baseproduct | grep -v "SLES_SAP.prod" 1> /dev/null
    then
        cd /etc/products.d 2>&1
        unlink baseproduct 2>&1
        ln -s SLES_SAP.prod baseproduct 2>&1
        registercloudguest --force-new 2>&1
    fi
fi
# -------------------------------------------------------------------------- #

#Check to see if this is a BYOS system and register it if it is
if [[ "$MyOS" =~ BYOS ]];
then
    _SUSE_BYOS=$(set_SUSE_BYOS)
    if [ "$_SUSE_BYOS" == 0 ]
    then
	    echo "Successfully setup BYOS"
    else
	    echo "FAILED to setup BYOS...exiting"
	    #signal the waithandler, 1=Failed
        /root/install/signalFinalStatus.sh 1 "FAILED to setup BYOS...exiting"
	    exit 1
    fi
fi

#the cli needs to be updated for SuSE in order to call ssm correctly
#the cli needs to be updated in order to call ssm correctly
echo
echo "Start set_update_cli @ $(date)"
echo
set_update_cli
_AWS_CLI=$(aws --version 2>&1)
if [ -n "$_AWS_CLI" ]
then
    echo "AWS CLI successfully updated"
else
	echo "**AWS CLI not updated correctly...EXITING**"
    /root/install/signalFinalStatus.sh 1 "**AWS CLI not updated correctly...EXITING**"
    exit 1
fi

set_oss_configs

#test copy some logs
#recreat the SSM param store as encrypted
_MPINV=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $1}' | grep INVALID | wc -l)
_MPVAL=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $NF}' | wc -l)
while [ "$_MPVAL" -eq 0 -a "$_MPINV" -eq 0 ]
do
    echo "Waiting for SSM parameter store: $SSM_PARAM_STORE @ $(date)..."
	_MPINV=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $1}' | grep INVALID | wc -l)
	sleep 15
done

#Save the password
#_MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $NF}')
##The password used to be in $NF but moved to $4
#_MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $4}')
_MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output table | grep Value | awk '{ print $4}')
#Delete the existing SSM param store
aws ssm delete-parameter --name $SSM_PARAM_STORE --region $REGION
#Recreate SSM param store
#Created an encrypted parameter_store for the master password
aws ssm put-parameter --name $SSM_PARAM_STORE  --type "SecureString" --value "$_MP" --region $REGION 
#Store the pass for the SAP param files
#MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output text | awk '{ print $NF}')
##The password used to be in $NF but moved to $4
MP=$(aws ssm get-parameters --names $SSM_PARAM_STORE --with-decryption --region $REGION --output table | grep Value | awk '{ print $4}')

echo
echo "Start set_install_jq @ $(date)"
echo
set_install_jq

_SET_UUIDD=$(set_uuidd)
if [ "$_SET_UUIDD" == 0 ]
then
    systemctl enable uuidd
    systemctl start uuidd
    _UUID_UP=$(ps -ef | grep uuidd | grep -iv grep)
    if [ "$_UUID_UP" ]
    then
        echo "Success, uuidd daemon install...will configure uuidd to auto start"
    fi
else 
    echo "FAILED, to install uuidd...exiting..."
fi

echo
echo "Start set_tz @ $(date)"
echo
_SET_TZ=$(set_tz)
if [ "$_SET_TZ" == 0 ]
then
    echo "Success, current TZ = $_CURRENT_TZ"
else
    echo "FAILED, current TZ = $_CURRENT_TZ"
    /root/install/signalFinalStatus.sh 1 "FAILED, current TZ = $_CURRENT_TZ"
    exit
fi

_SET_AWSDP=$(set_awsdataprovider)
if [ "$_SET_AWSDP" == 0 ]
then
    echo "Successfully installed AWS Data Provider"
else
    echo "FAILED to install AWS Data Provider...exiting"
    /root/install/signalFinalStatus.sh 1 "FAILED to install AWS Data Provider...exiting"
    exit
fi

_SET_DNS_=$(set_net)

if Implement_Chrony
then
    echo "Successfully implemented Chrony!!"
else
    echo "FAILED: Chrony NOT implmented!!"
    /root/install/signalFinalStatus.sh 1 "FAILED: Chrony NOT implemented!!"
    exit
fi

# 
# Replacing NTP by Chrony, that is a better solution and recommended by AWS  
#
#_SET_NTP=$(set_ntp)
#if [ "$_SET_NTP" == 0 ]
#then
#    echo "Successfully set NTP"
#else
#    
#fi

echo
echo "Start set_hostname @ $(date)"
echo
_SET_HOSTNAME=$(set_hostname)

if [ "$_SET_HOSTNAME" == 0 ]
then
    echo "Successfully set and updated hostname"
else
    echo "FAILED to set hostname"
    /root/install/signalFinalStatus.sh 1 "FAILED to set hostname"
    exit
fi

#We need to determine if we are using EFS or a local /sapmnt
if [ "$EFS" == "Yes" ]
then
    echo
    echo "Start set_EFS @ $(date)"
    echo
    _SET_EFS=$(set_EFS)

    _SAPMNT=$(df -h $SAPMNT | awk '{ print $NF }' | tail -1)

    if [ "$_SAPMNT" == "$SAPMNT"  ]
    then
	    echo "Successfully setup /sapmnt"
    else
	    echo "Failed to mount $SAPMNT...exiting"
	    #signal the waithandler, 1=Failed
       	/root/install/signalFinalStatus.sh 1 "Failed to _SET_EFS for /sapmnt with EFS filesystem: $EFS_MP"
	    set_cleanup_ascsinifile
	    exit 1
    fi
else
    echo
    echo "Start set_filesystems @ $(date)"
    echo
    if set_filesystems
    then
        echo "Successfully created $USR_SAP and $SAPMNT"
        echo
        echo "Start set_nfsexport @ $(date)"
        echo
        _SET_NFS=$(set_nfsexport)
        SHOWMOUNT=$(showmount -e | wc -l)

        if [ "$_SET_NFS" == 0 -a $SHOWMOUNT -ge 2 ]
        then
            echo "Successfully exported NFS file(s)"
        else
            echo "FAILED to export NFS file(s)"
            /root/install/signalFinalStatus.sh 1 "FAILED to export NFS file(s)"
            echo "FAILED to set NFS export /sapmnt..."
            /root/install/signalFinalStatus.sh 1 "Failed to NFS_EXPORT /sapmnt"
            exit 1
        fi
    else
        echo
     	echo "FAILED to set /usr/sap and /sapmnt..."
        /root/install/signalFinalStatus.sh 1 "Failed to _SET_FS for /sapmnt"
        exit 1
	fi
fi

echo
echo "Start set_s3_download @ $(date)"
echo
_SET_S3=$(set_s3_download)

if [ "$_SET_S3" == 0 ]
then
    echo "Successfully downloaded the s/w"
else
    echo
    echo "FAILED to download the s/w..."
    echo "check /sapmnt/SWPM and permissions to your S3 SAP software bucket and key prefix:"$S3_BUCKET"/"$S3_BUCKET_KP" "
    #log the error message
    aws s3 sync "s3://${S3_BUCKET}/${S3_BUCKET_KP}" "$SW_TARGET" > /tmp/nw_s3_downnload_error.log 2>&1
    S3_ERR=$(cat /tmp/nw_s3_downnload_error.log)
    #signal the waithandler, 1=Failed
    /root/install/signalFinalStatus.sh 1 \""FAILED to set /usr/sap and /sapmnt...check /sapmnt/SWPM and permissions to your S3 SAP software bucket:"$S3_BUCKET"/"$S3_BUCKET_KP" ERR= \"$S3_ERR\" "\"
    set_cleanup_inifiles
    exit
fi

echo
echo "Start set_install_ssm @ $(date)"
echo
set_install_ssm

###Execute sapinst###

if [ "$INSTALL_SAP" == "No" ]
then
	echo "Completed setting up SAP App Server Infrastrucure."
	echo "Exiting as the option to install SAP software was set to: $INSTALL_SAP"
	#signal the waithandler, 0=Success
	/root/install/signalFinalStatus.sh 0 "Finished. Exiting as the option to install SAP software was set to: $INSTALL_SAP"
        exit 0
fi

#**Install the ASCS and DB Instances**

#SID=$(echo "$SAP_SID" |tr '[:upper:]' '[:lower:]')
#SIDADM=$(echo $SID\adm)
SIDADM=`echo ${SAP_SID} | tr '[:upper:]' '[:lower:]'`adm

set_ascsinifile
set_dbinifile
set_pasinifile

#Install the ASCS and DB Instances

umask 006

cd $SAPINST
sleep 5

#support multilple NW versions

echo "Installing the ASCS instance...(1st try)"
./sapinst SAPINST_INPUT_PARAMETERS_URL="$ASCS_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$ASCS_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false

#test if SAP is up
_SAP_UP=$(netstat -an | grep 32"$SAPInstanceNum" | grep tcp | grep LISTEN | wc -l )

echo "This is the value of SAP_UP: $_SAP_UP"

if [ "$_SAP_UP" -eq 1 ]
then
    echo "Successfully installed SAP" >> /tmp/install-single-hosts.log

    #Proceed with the Database Install

    mv /tmp/sapinst_instdir /tmp/ascs1-sapinst_instdir

    rm -rf /tmp/sap*
    echo "ls -l of /tmp/sapinst after rm..."
    ls -l /tmp/*
    echo
    echo "Proceeding with database installation...(1st try)"

    #Prior to start of install...copy some logs
    ./sapinst SAPINST_INPUT_PARAMETERS_URL="$DB_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$DB_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false
  
    DB_DONE=$(su - "$SIDADM" -c "R3trans -d" | grep "R3trans finished (0000)")

    if [[ "$DB_DONE" =~ finished ]];
    then
        echo "DB installed" >> /tmp/install-single-hosts.log
        #create the ASCS DONE file
        touch "$ASCS_DONE"
    fi
else
    echo "RETRY SAP install..."
    
    mv /tmp/sapinst_instdir /tmp/1ascs-sapinst_instdir
    
    rm -rf /tmp/sap*
    echo "ls -l of /tmp/sapinst after rm..."
    ls -l /tmp/*
#    chmod 6770 /tmp
#    chgrp sapinst /tmp
#    cd $SAPINST
    sleep 5

    echo "Installing the ASCS instance...(2nd try)"
    ./sapinst SAPINST_INPUT_PARAMETERS_URL="$ASCS_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$ASCS_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false
    sleep 5
    #test if SAP is up
    _SAP_UP=$(netstat -an | grep 32"$SAPInstanceNum" | grep tcp | grep LISTEN | wc -l )

    echo "This is the value of SAP_UP: $_SAP_UP"

    if [ "$_SAP_UP" -eq 1 ]
    then
        echo "ASCS installed after 2nd retry..."
    else
        _ERR_LOG=$(find /tmp -type f -name "sapinst_dev.log")
	    _PASS_ERR=$(grep ERR "$_ERR_LOG" | grep -i password)
        /root/install/signalFinalStatus.sh 1 "SAP ASCS install RETRY Failed...ASCS not installed 2nd retry...password error?= "$_PASS_ERR" "
        exit 1
    fi

    #Proceed with the Database Install
    cd /tmp

    mv /tmp/sapinst_instdir /tmp/2ascs-sapinst_instdir

    rm -rf sap*
    cd $SAPINST
    #Prior to start of install...copy some logs
    echo "Proceeding with database installation...(2nd try)"
    ./sapinst SAPINST_INPUT_PARAMETERS_URL="$DB_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$DB_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false
     
    #Check the DB 
    DB_DONE=$(su - $SIDADM -c "R3trans -d" | grep "R3trans finished (0000)")

    if [[ "$DB_DONE" =~ finished ]];
    then
        echo "DB installed"
        #create the ASCS DONE file
        touch "$ASCS_DONE"
    else
        echo "DB not installed."

        #set_cleanup_inifiles

        #/root/install/signalFinalStatus.sh 1 "SAP install RETRY Failed...DB not installed."
        DB_DONE_ERR=$(su - $SIDADM -c "R3trans -d" > /tmp/sap_r3trans.log 2>&1 )
        DB_DONE_LOG=$(cat /tmp/sap_r3trans.log )
        /root/install/signalFinalStatus.sh 1 "SAP install RETRY Failed...DB not installed...LOG= "$DB_DONE_LOG" "
        exit 1
    fi
fi


#exit if the ASCS_DONE file is not created
if [ ! -e "$ASCS_DONE" ]
then
    echo "checking $ASCS_DONE file..."
    _FILE=$(ls -l "$ASCS_DONE")
    echo $_FILE

    echo "$ASCS_DONE file does not exist...exiting"

    #set_cleanup_inifiles

    /root/install/signalFinalStatus.sh 1 "ASCS_DONE file $ASCS_DONE does not exist...exiting"
    exit 1
fi

#Proceed with the PAS Install

#Save the sap entries in /etc/services to the /sapmnt share for PAS and ASCS instances
_SET_SERVICES=$(set_save_services_file)

if [ "$_SET_SERVICES" == 0 ]
then
    echo "Successfully set services file"
else
    echo  "FAILED to set services file"
    set_cleanup_inifiles
    /root/install/signalFinalStatus.sh 1 "FAILED to set services file"
    exit 1
fi

cd /tmp

mv /tmp/sapinst_instdir /tmp/db-sapinst_instdir

rm -rf sap*
cd $SAPINST
sleep 5

#save logs to s3 bucket
./sapinst SAPINST_INPUT_PARAMETERS_URL="$PAS_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PAS_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false

#test if SAP is up
_SAP_UP=$(netstat -an | grep 32"$(printf "%02d" $(( 10#${SAPInstanceNum} + 1 )))" | grep tcp | grep LISTEN | wc -l )

if [ "$_SAP_UP" -eq 1 ]
then
	echo "Successfully installed SAP"
	#create the PAS done file
	touch "$PAS_DONE"
	#signal the waithandler, 0=Success
	/root/install/signalFinalStatus.sh 0 "Successfully installed SAP. First try..."
    set_cleanup_inifiles
	#create the /etc/sap-app-quickstart file
	touch /etc/sap-app-quickstart
	chmod 1777 /tmp
	mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket
	#save logs to s3 bucket
	exit
else
	echo "RETRY SAP install..."

	cd /tmp
	rm -rf sap*
	cd $SAPINST
	sleep 5

	./sapinst SAPINST_INPUT_PARAMETERS_URL="$PAS_INI_FILE" SAPINST_EXECUTE_PRODUCT_ID="$PAS_PRODUCT" SAPINST_SKIP_DIALOGS=true SAPINST_START_GUISERVER=false

	#test if SAP is up
	_SAP_UP=$(netstat -an | grep 32"$(printf "%02d" 10#${SAPInstanceNum} + 1 )))" | grep tcp | grep LISTEN | wc -l )

	echo "This is the value of SAP_UP: $_SAP_UP"

	if [ "$_SAP_UP" -eq 1 ]
	then
		#create the PAS done file
		touch "$PAS_DONE"
		#signal the waithandler, 0=Success
		/root/install/signalFinalStatus.sh 0 "SAP successfully install...after RETRY"
        set_cleanup_inifiles
		#create the /etc/sap-app-quickstart file
		touch /etc/sap-app-quickstart
		chmod 1777 /tmp
		mv /var/run/dbus/system_bus_socket.bak /var/run/dbus/system_bus_socket
    else
		echo "SAP PAS failed to install...exiting"
		#signal the waithandler, 1=Failed
		/root/install/signalFinalStatus.sh 1 "SAP PAS failed to install...exiting"
                set_cleanup_inifiles
		exit
    fi
fi




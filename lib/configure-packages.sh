function print-configure-bridge-message() {
	echo "*********************************************************************************"
        echo "If you configured OVS as the Neutron ML2 mechanism driver, do not forget to run the following command:"
        echo "sudo bash $(dirname $0)/configure-ovs-bridge.sh <interfacename>" 
	echo "Example: sudo bash $(dirname $0)/configure-ovs-bridge.sh eth1"
	echo "*********************************************************************************"
}

source $(dirname $0)/config-parameters.sh
if [ $# -ne 1 ]
	then
		echo "Correct syntax: $0 [ controller | compute | networknode ]"
		exit 1;
fi

metering_secret="password"

if [ "$1" == "compute" ]
	then
		echo_and_sleep "About to configure Compute" 3
		bash $(dirname $0)/configure-forwarding.sh compute

		echo_and_sleep "About to configure Nova for Compute" 3
		bash $(dirname $0)/configure-nova.sh compute $controller_host_name $nova_password $rabbitmq_password
		
		echo_and_sleep "About to configure Neutron for Compute" 3
		bash $(dirname $0)/configure-neutron.sh compute $controller_host_name $rabbitmq_password $neutron_password
		
		echo_and_sleep "About to configure Ceilometer for Compute" 3
		bash $(dirname $0)/configure-ceilometer.sh compute $controller_host_name $rabbitmq_password $neutron_password $metering_secret
fi

if [ "$1" == "controller" ] 
	then
		echo_and_sleep "About to configure Controller"	
                mysql_conf_file="/etc/mysql/mariadb.conf.d/mysqld.cnf"
                if [ -f "$mysql_conf_file" ]
                then
			echo_and_sleep “Maria DB Conf file found” 2
                else
                        mysql_conf_file="/etc/mysql/my.cnf"
                fi
                echo "Updating MySQL Config File...: $mysql_conf_file"
		sed -i "s/127.0.0.1/0.0.0.0/g" $mysql_conf_file
		echo_and_sleep "Updated Bind Address" 2
		grep "bind" $mysql_conf_file
		
		sed -i "/\[mysqld\]/a default-storage-engine = innodb\\
				innodb_file_per_table\\
				collation-server = utf8_general_ci\\
				init-connect = 'SET NAMES utf8'\\
				character-set-server = utf8\\
		" $mysql_conf_file
		echo_and_sleep "Updated other MySQL Parameters" 2
		grep "storage-engine" $mysql_conf_file
		
		echo_and_sleep "Restarting MySQL and securing installation..."
		service mysql restart;
		sleep 5
		mysql_secure_installation;
		
		echo_and_sleep "Rabbit MQ: Updating password: $rabbitmq_password"
		rabbitmqctl add_user $rabbitmq_user $rabbitmq_password
		echo_and_sleep "Rabbit MQ: User Added. About to set Permissions"
		rabbitmqctl set_permissions $rabbitmq_user ".*" ".*" ".*"
		echo_and_sleep "Configured Permissions in Rabbit MQ"
		service rabbitmq-server restart
		
				
		echo_and_sleep "About to setup KeyStone..."
		bash $(dirname $0)/configure-keystone.sh $keystone_db_password $mysql_user $mysql_password $controller_host_name $admin_tenant_password
		
		echo_and_sleep "About to setup Glance..."
		bash $(dirname $0)/configure-glance.sh $glance_db_password $mysql_user $mysql_password $controller_host_name $admin_tenant_password $glance_password
		
		echo_and_sleep "About to setup NOVA..."
		bash $(dirname $0)/configure-nova.sh controller $controller_host_name $nova_password $rabbitmq_password $nova_db_password $mysql_user $mysql_password 
		
		echo_and_sleep "About to setup Neutron..."
		source $(dirname $0)/admin_openrc.sh
		service_tenant_id=`keystone tenant-get service | grep id | cut -d '|' -f3 | tr -s ' '`
		echo_and_sleep "Service Tenant ID is: $service_tenant_id" 7
		bash $(dirname $0)/configure-neutron.sh controller $controller_host_name $rabbitmq_password $neutron_password $neutron_db_password $mysql_user $mysql_password $service_tenant_id
		
		echo_and_sleep "About to setup Horizon-Dashboard"
		bash $(dirname $0)/configure-horizon.sh $controller_host_name
		
		echo_and_sleep "About to setup Ceilometer..."
		bash $(dirname $0)/configure-ceilometer.sh controller $controller_host_name $rabbitmq_password $neutron_password $metering_secret $ceilometer_db_password
fi

if [ "$1" == "networknode" ]
	then
		echo_and_sleep "About to configure Network Node"
		bash $(dirname $0)/configure-forwarding.sh networknode

		echo_and_sleep "About to configure Neutron for Network Node" 2
		bash $(dirname $0)/configure-neutron.sh networknode $controller_host_name $rabbitmq_password $neutron_password

fi
print-configure-bridge-message

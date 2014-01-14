zabbix-utils
============

Various utilities related to Zabbix monitoring system

zabbix-partition.sh
-------------------
This is script to generate initial configuration and following daily/monthly updates for partitioning zabbix DB for mysql. Defaul binary is set to `mysql`, if you want to specify path or just se what the script tries to run use `-b` switch.

### How To:
- Run initial partitioning like `./zabbix-partition.sh -i -c /etc/zabbix/zabbix_server.conf` (change the -c path to point to the zabbix config file containing your DB credentials).
- Setup daily cron job to run `./zabbix-partition.sh -c /etc/zabbix/zabbix_server.conf`

### Basic usage:
- `./zabbix-partition.sh -i` will try to run initially partition the database (this needs to be done before running daily/monthly updates)
- - `./zabbix-partition.sh` will try to run daily partitioning update with default values
- `./zabbix-partition.sh -b echo` will print commands that the script tries to run
- For rest use `./zabbix-partition.sh -h`, which will display help

```
zabbix-partition.sh [-i] [-d #] [-e #] [-f #] [-m #] [-n #] [-o #] [-p] [-U #] [-P #] [-D #]
-b	- binary to use (default mysql)
-c	- zabbix config file with DB credentials
-d	- number of days to keep (default is 90)
-e	- number of daily partitions to create ahead (default is 1)
-f	- number of daily partitions to drop (default is 1)
-h	- prints this help
-i	- generate initial configuration instead of daily one
-m	- number of months to keep (default is 12)
-n	- number of monthly partitions to create ahead (default is 1)
-o	- number of monthly partitions to drop (default is 1)
-p	- force generation of monthly commands (normally these are generated only on 1st)
-U	- DB username (default zabbix)
-P	- DB password (default zabbix)
-D	- DB name (default zabbix)
```

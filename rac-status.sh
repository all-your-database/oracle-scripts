#!/bin/bash
# Fred Denis -- Jan 2016 -- http://unknowndba.blogspot.com -- fred.denis3@gmail.com
#
#
# Quickly shows a status of all running instances accross a 12c cluster
# The script just need to have a working oraenv
#
# Please have a look at https://unknowndba.blogspot.com/2018/04/rac-statussh-overview-of-your-rac-gi.html for some details and screenshots
# The script last version can be downloaded here : https://raw.githubusercontent.com/freddenis/oracle-scripts/master/rac-status.sh
#
# The current script version is 20181010
#
# History :
#
# 20181011 - Jon Fife   - Add ASM to DB list
# 20181011 - Jon Fife   - Option to create DB/SID/service aliases to set environment
# 20181010 - Jon Fife   - Integrate service and DB output
# 20181010 - Fred Denis - Added the services
#                         Added default values and options to show and hide some resources (./rac-status.sh -h for more information)
# 20181009 - Fred Denis - Show the usual blue "-" when a target is offline on purpose instead of a red "Offline" which was confusing
# 20180921 - Fred Denis - Added the listeners
# 20180227 - Fred Denis - Make the the size of the DB column dynamic to handle very long database names (Thanks Michael)
#                       - Added a (P) for Primary databases and a (S) for Stanby for color blind people who
#                         may not see the difference between white and red (Thanks Michael)
# 20180225 - Fred Denis - Make the multi status like "Mounted (Closed),Readonly,Open Initiated" clear in the table by showing only the first one
# 20180205 - Fred Denis - There was a version alignement issue with more than 10 different ORACLE_HOMEs
#                       - Better colors for the label "White for PRIMARY, Red for STANBY"
# 20171218 - Fred Denis - Modify the regexp to better accomodate how the version can be in the path (cannot get it from crsctl)
# 20170620 - Fred Denis - Parameters for the size of the columns and some formatting
# 20170619 - Fred Denis - Add a column type (RAC / RacOneNode / Single Instance) and color it depending on the role of the database
#                         (WHITE for a PRIMARY database and RED for a STANDBY database)
# 20170616 - Fred Denis - Shows an ORACLE_HOME reference in the Version column and an ORACLE_HOME list below the table
# 20170606 - Fred Denis - A new 12cR2 GI feature now shows the ORACLE_HOME in the STATE_DETAILS column from "crsctl -v"
#                       - Example :     STATE_DETAILS=Open,HOME=/u01/app/oracle/product/11.2.0.3/dbdev_1 instead of STATE_DETAILS=Open in 12cR1
# 20170518 - Fred Denis - Add  a readable check on the ${DBMACHINE} file - it happens that it exists but is only root readable
# 20170501 - Fred Denis - First release
#

      TMP=/tmp/status$$.tmp                                             # A tempfile
DBMACHINE=/opt/oracle.SupportTools/onecommand/databasemachine.xml       # File where we should find the Exadata model as oracle user

# An usage function
usage()
{
printf "\n\033[1;37m%-8s\033[m\n" "NAME"                ;
cat << END
        `basename $0` - A nice overview of databases, listeners and services running across a GI 12c
END

printf "\n\033[1;37m%-8s\033[m\n" "SYNOPSIS"            ;
cat << END
        $0 [-a] [-n] [-d] [-l] [-s] [-h]
END

printf "\n\033[1;37m%-8s\033[m\n" "DESCRIPTION"         ;
cat << END
        `basename $0` needs to be executed with a user allowed to query GI using crsctl; oraenv also has to be working
        `basename $0` will show what is running or not running accross all the nodes of a GI 12c :
                - The databases instances (and the ORACLE_HOME they are running against)
                - The type of database : Primary, Standby, RAC One node, Single
                - The listeners (SCAN Listener and regular listeners)
                - The services
        With no option, `basename $0` will show what is defined by the variables :
                - SHOW_DB       # To show the databases instances
                - SHOW_LSNR     # To show the listeners
                - SHOW_SVC      # To show the services
		- SHOW_ASM	# To show ASM in the DB output
		- INT_DB_SVC	# To show services in the DB output
		- SET_ALIAS	# To create aliases for setting up DB environment variables
                These variables can be modified in the script itself or you can use command line option to revert their value (see below)

END

printf "\n\033[1;37m%-8s\033[m\n" "OPTIONS"             ;
cat << END
        -a        Show everything regardless of the default behavior defined with SHOW_DB, SHOW_LSNR and SHOW_SVC
        -n        Show nothing    regardless of the default behavior defined with SHOW_DB, SHOW_LSNR and SHOW_SVC
        -d        Revert the behavior defined by SHOW_DB  ; if SHOW_DB   is set to YES to show the databases by default, then the -d option will hide the databases
        -l        Revert the behavior defined by SHOW_LSNR; if SHOW_LSNR is set to YES to show the listeners by default, then the -l option will hide the listeners
        -s        Revert the behavior defined by SHOW_SVC ; if SHOW_SVC  is set to YES to show the services  by default, then the -s option will hide the services
	-e	  Create aliases for DB, Instance, and Services to set DB environments
	-i        Integrate the DB and service output
        -h        Shows this help

        Note : the options are cumulative and can be combined with a "the last one wins" behavior :
                $ $0 -a -l              # Show everything but the listeners (-a will force show everything then -l will hide the listeners)
                $ $0 -n -d              # Show only the databases           (-n will force hide everything then -d with show the databases)

                Experiment and enjoy  !

END
exit 123
}

# Choose the information what you want to see -- the last uncommented value wins
# ./rac-status.sh -h for more information
  SHOW_DB="YES"                 # Databases
 #SHOW_DB="NO"
SHOW_LSNR="YES"                 # Listeners
#SHOW_LSNR="NO"
# SHOW_SVC="YES"                 # Services
 SHOW_SVC="NO"
 SET_ALIAS="NO"
 SHOW_ASM="NO"
 INT_DB_SVC="NO"

# Options
while getopts "andslhiem" OPT; do
        case ${OPT} in
        a)         SHOW_DB="YES"        ; SHOW_LSNR="YES"       ; SHOW_SVC="YES"                ;;
        n)         SHOW_DB="NO"         ; SHOW_LSNR="NO"        ; SHOW_SVC="NO"                 ;;
        d)         if [ "$SHOW_DB"   = "YES" ]; then   SHOW_DB="NO"; else   SHOW_DB="YES"; fi   ;;
        s)         if [ "$SHOW_SVC"  = "YES" ]; then  SHOW_SVC="NO"; else  SHOW_SVC="YES"; fi   ;;
        l)         if [ "$SHOW_LSNR" = "YES" ]; then SHOW_LSNR="NO"; else SHOW_LSNR="YES"; fi   ;;
        i)         INT_DB_SVC="YES"                                                             ;;
	e)	   SET_ALIAS="YES"								;;
        m)         if [ "$SHOW_ASM" = "YES" ]; then SHOW_ASM="NO"; else SHOW_ASM="YES"; fi   ;;
        h)         usage                                                                        ;;
        \?)        echo "Invalid option: -$OPTARG" >&2; usage                                   ;;
        esac
done
#
# Set the ASM env to be able to use crsctl commands
#
ORACLE_SID=`ps -ef | grep pmon | grep asm | awk '{print $NF}' | sed s'/asm_pmon_//' | egrep "^[+]"`

export ORAENV_ASK=NO
. oraenv > /dev/null 2>&1

#
# List of the nodes of the cluster
#
NODES=`olsnodes | awk '{if (NR<2){txt=$0} else{txt=txt","$0}} END {print txt}'`

#
# Show the Exadata model if possible (if this cluster is an Exadata)
#
if [ -f ${DBMACHINE} ] && [ -r ${DBMACHINE} ]
then
        cat << !

                Cluster is a `grep -i MACHINETYPES ${DBMACHINE} | sed -e s':</*MACHINETYPES>::g' -e s'/^ *//' -e s'/ *$//'`

!
else
        printf "\n"
fi

# Get the info we want
cat /dev/null                                                   >  $TMP
if [ "$SHOW_DB" = "YES" ]
then
	if [ "$SHOW_ASM" = "YES" ]; then
		echo NAME=asm					>> $TMP
		echo " "					>> $TMP
		echo ACL=foo					>> $TMP
		echo ORACLE_HOME=$ORACLE_HOME			>> $TMP
		echo DATABASE_TYPE=ASM				>> $TMP
		echo ROLE=PRIMARY				>> $TMP
		crsctl stat res -p -w "TYPE = ora.asm.type"	>> $TMP
		
		crsctl stat res -v -w "TYPE = ora.asm.type"	>> $TMP
	fi
        crsctl stat res -p -w "TYPE = ora.database.type"        >> $TMP
        crsctl stat res -v -w "TYPE = ora.database.type"        >> $TMP
        crsctl stat res -v -w "TYPE = ora.service.type"         >> $TMP
fi
if [ "$SHOW_LSNR" = "YES" ]
then
        crsctl stat res -v -w "TYPE = ora.listener.type"        >> $TMP
        crsctl stat res -p -w "TYPE = ora.listener.type"        >> $TMP
        crsctl stat res -v -w "TYPE = ora.scan_listener.type"   >> $TMP
        crsctl stat res -p -w "TYPE = ora.scan_listener.type"   >> $TMP
fi
if [[ "$SHOW_SVC" = "YES" && "$SHOW_DB" = "NO" ]]
then
        crsctl stat res -v -w "TYPE = ora.service.type"         >> $TMP
        #crsctl stat res -p -w "TYPE = ora.service.type"        >> $TMP         # not used, in case we need it one day
fi

        gawk  -v NODES="$NODES" -v SHOW_SVC="$SHOW_SVC" -v INT_DB_SVC="$INT_DB_SVC" -v HOST=$(hostname) 'BEGIN\
        {             FS = "="                          ;
                      split(NODES, nodes, ",")          ;       # Make a table with the nodes of the cluster
                # some colors
             COLOR_BEGIN =       "\033[1;"              ;
               COLOR_END =       "\033[m"               ;
                     RED =       "31m"                  ;
                   GREEN =       "32m"                  ;
                  YELLOW =       "33m"                  ;
                    BLUE =       "34m"                  ;
                    TEAL =       "36m"                  ;
                   WHITE =       "37m"                  ;

                 UNKNOWN = "-"                          ;       # Something to print when the status is unknown

                # Default columns size
                COL_NODE = 18                           ;
                  COL_DB = 10                           ;
                 COL_VER = 15                           ;
                COL_TYPE = 14                           ;
		COL_SVC = 15				;
        }

        #
        # A function to center the outputs with colors
        #
        function center( str, n, color)
        {       right = int((n - length(str)) / 2)                                                              ;
                left  = n - length(str) - right                                                                 ;
                return sprintf(COLOR_BEGIN color "%" left "s%s%" right "s" COLOR_END "|", "", str, "" )         ;
        }

        #
        # A function that just print a "---" white line
        #
        function print_a_line(size)
        {
                if ( ! size)
                {       
			if (length(INT_DB_SVC) > 2)
			{	size = COL_DB+COL_SVC+COL_VER+(COL_NODE*n)+COL_TYPE+n+4                         ;
			} else {
				size = COL_DB+COL_VER+(COL_NODE*n)+COL_TYPE+n+3				;
			}
                }
                printf("%s", COLOR_BEGIN WHITE)                                                                 ;
                for (k=1; k<=size; k++) {printf("%s", "-");}                                                    ;       # n = number of nodes
                printf("%s", COLOR_END"\n")                                                                     ;
        }
        {
               # Fill 2 tables with the OH and the version from "crsctl stat res -p -w "TYPE = ora.database.type""
               if ($1 ~ /^NAME/)
               {
                        sub("^ora.", "", $2)                                                                    ;
                        sub(".db$", "", $2)                                                                     ;
                        if ($2 ~ ".lsnr"){sub(".lsnr$", "", $2); tab_lsnr[$2] = $2}                             ;       # Listeners
                        if ($2 ~ ".svc") {sub(".svc$", "", $2) ; tab_svc[$2] = $2;
                                          split($2, temp, ".");

					  if (length(tab_svc_db[temp[1]]) > 0)
					  {	tab_svc_db[temp[1]]=tab_svc_db[temp[1]] "," temp[2];
					  } else 
					  { 	tab_svc_db[temp[1]]=temp[2];
					  }

                                          if (length(temp[2]) > max_length_svc)                                         # To adapt the column size
                                          {     max_length_svc = length(temp[2])                                ;
                                          }

					  if (length(tab_svc_db[temp[1]]) > max_length_svcs)
					  {	max_length_svcs = length(tab_svc_db[temp[1]])			;
					  }
                                         }                                                                              # Services
                        DB=$2                                                                                   ;
                        if (length(DB)+2 > COL_DB)              # Adjust the size of the DB column in case of very long DB name
                        {                                       # +2 is to have 1 blank character before and after the DB name
                                COL_DB = length(DB)+2                                                           ;
                        }

                        getline; getline                                                                        ;
                        if ($1 == "ACL")                        # crsctl stat res -p output
                        {
                                if ((DB in version == 0) && (DB in tab_lsnr == 0) && (DB in tab_svc == 0))
                                {
                                        while (getline)
                                        {
                                                if ($1 == "ORACLE_HOME")
                                                {                    OH = $2                                    ;
                                                        match($2, /1[0-9]\.[0-9]\.?[0-9]?\.?[0-9]?/)            ;       # Grab the version from the OH path)
                                                                VERSION = substr($2,RSTART,RLENGTH)             ;
                                                }
                                                if ($1 == "DATABASE_TYPE")                                              # RAC / RACOneNode / Single Instance are expected here
                                                {
                                                             dbtype[DB] = $2                                    ;
                                                }
                                                if ($1 == "ROLE")                                                       # Primary / Standby expected here
                                                {              role[DB] = $2                                    ;
                                                }
						if ($1 ~ /USR_ORA_INST_NAME@SERVERNAME/)
						{ 	
							if ($1 ~ HOST) {	
								alias[$2] = OH					;	
								alias2[DB]=$2					;
							}
						}
                                                if ($0 ~ /^$/)
                                                {           version[DB] = VERSION                               ;
                                                                 oh[DB] = OH                                    ;

                                                        if (!(OH in oh_list))
                                                        {
                                                                oh_ref++                                        ;
                                                            oh_list[OH] = oh_ref                                ;
                                                        }
                                                        break                                                   ;
                                                }
	
                                        }
                                }
                                if (DB in tab_lsnr == 1)
                                {
                                        while(getline)
                                        {
                                                if ($1 == "ENDPOINTS")
                                                {
                                                        port[DB] = $2                                           ;
                                                        break                                                   ;
                                                }
                                        }
                                }
                        }
                        if ($1 == "LAST_SERVER")        # crsctl stat res -v output
                        {           NB = 0      ;       # Number of instance as CARDINALITY_ID is sometimes irrelevant
                                SERVER = $2     ;
                                while (getline)
                                {
                                        if ($1 == "LAST_SERVER")        {       SERVER = $2                             ;}
                                        if ($1 == "STATE")              {       gsub(" on .*$", "", $2)                 ;
                                                                                if ($2 ~ /ONLINE/ ) {STATE="Online"     ;}
                                                                                if ($2 ~ /OFFLINE/) {STATE=""           ;}
                                                                        }
                                        if ($1 == "TARGET")             {       TARGET = $2                             ;}
                                        if ($1 == "STATE_DETAILS")      {       NB++                                    ;       # Number of instances we came through
                                                                                sub("STATE_DETAILS=", "", $0)           ;
                                                                                if ($0 == "")
                                                                                {       status[DB,SERVER] = STATE       ;}
                                                                                else {
                                                                                        status[DB,SERVER] = $0          ;}
                                                                                }
                                        if ($1 == "INSTANCE_COUNT")     {       if (NB == $2) { break                   ;}}
                                }
                        }
                }       # End of if ($1 ~ /^NAME/)
            }
            END {       if (length(tab_lsnr) > 0)                # We print only if we have something to show
                        {
                                # A header for the listeners
                                printf("%s", center("Listener" ,  COL_DB, WHITE))                               ;
                                printf("%s", center("Port"     , COL_VER, WHITE))                               ;
                                n=asort(nodes)                                                                  ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                         ;
                                }
                                printf("%s", center("Type"    , COL_TYPE, WHITE))                               ;
                                printf("\n")                                                                    ;

                                # a "---" line under the header
                                print_a_line()                                                                  ;

                                # print the listeners
                                x=asorti(tab_lsnr, lsnr_sorted)                                                 ;
                                for (j = 1; j <= x; j++)
                                {
                                        printf("%s", center(lsnr_sorted[j]   , COL_DB, WHITE))                  ;       # Listener name
                                        printf(COLOR_BEGIN WHITE " %-8s" COLOR_END, port[lsnr_sorted[j]], COL_VER, WHITE);      # Port
                                        printf(COLOR_BEGIN WHITE "%6s" COLOR_END"|","")                         ;       # Nothing

                                        for (i = 1; i <= n; i++)
                                        {
                                                dbstatus = status[lsnr_sorted[j],nodes[i]]                      ;

                                                if (dbstatus == "")             {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Online")       {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}
                                                else                            {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        if (toupper(lsnr_sorted[j]) ~ /SCAN/)
                                        {       LSNR_TYPE = "SCAN Listener"                                     ;
                                        } else {
                                                LSNR_TYPE = "Listener"                                          ;
                                        }
                                        printf("%s", center(LSNR_TYPE, COL_TYPE, WHITE))                        ;
                                        printf("\n")                                                            ;
                                }
                                # a "---" line under the header
                                print_a_line()                                                                  ;
                                printf("\n")                                                                    ;
                        }

                        if (length(SHOW_SVC) > 2 && length(tab_svc) > 0)                # We print only if we have something to show
                        {
                                if (max_length_svc > COL_VER)
                                {       COL_SVC = max_length_svc                                                ;
                                } else {
                                        COL_SVC = COL_VER                                                       ;
                                }
                                # A header for the services
                                printf("%s", center("DB"      ,  COL_DB, WHITE))                                ;
                                printf("%s", center("Services" ,  COL_SVC, WHITE))                               ;
                                n=asort(nodes)                                                                  ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                         ;
                                }
                                printf("\n")

                                # a "---" line under the header
                                print_a_line(COL_DB+COL_NODE*n+COL_SVC+n+2)                                    ;


                                # Print the Services
                                x=asorti(tab_svc, svc_sorted)                                                   ;
                                for (j = 1; j <= x; j++)
                                {
                                        split(svc_sorted[j], to_print, ".")                                     ;       # The service we have is <db_name>.<service_name>
                                        if (previous_db != to_print[1])                                                 # Do not duplicate the DB names on the output
                                        {
                                                printf("%s", center(to_print[1], COL_DB, WHITE))                ;
                                                previous_db = to_print[1]                                       ;
                                        }else {
                                                printf("%s", center("",  COL_DB, WHITE))                        ;
                                        }
                                        printf("%s", center(to_print[2], COL_SVC, WHITE))                       ;


                                        for (i = 1; i <= n; i++)
                                        {
                                                dbstatus = status[svc_sorted[j],nodes[i]]                       ;

                                                if (dbstatus == "")             {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Online")       {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}
                                                else                            {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        printf("\n")                                                             ;
                                }
                                # a "---" line under the header
                                print_a_line(COL_DB+COL_NODE*n+COL_SVC+n+2)                                    ;
                                printf("\n")                                                                     ;
                        }

                        if (length(version) > 0)                # We print only if we have something to show
                        {
				if (max_length_svcs+2 > COL_VER)
                                {       COL_SVC = max_length_svcs+2                                              ;
                                } else {
                                        COL_SVC = COL_VER                                                       ;
                                }
                                # A header for the databases
                                printf("%s", center("DB"        , COL_DB, WHITE))                                ;
                                printf("%s", center("Version"   , COL_VER, WHITE))                               ;
				if (length(INT_DB_SVC) > 2) 
				{ 	printf("%s", center("Services"   , COL_SVC, WHITE))                               ;
				}
                                n=asort(nodes)                                                                   ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                          ;
                                }
                                printf("%s", center("DB Type"    , COL_TYPE, WHITE))                             ;
                                printf("\n")                                                                     ;

                                # a "---" line under the header
                                print_a_line()                                                                   ;

                                # Print the databases
                                m=asorti(version, version_sorted)                                                ;
                                for (j = 1; j <= m; j++)
                                {
                                        printf("%s", center(version_sorted[j]   , COL_DB, WHITE))                ;                       # Database name
                                        printf(COLOR_BEGIN WHITE " %-8s" COLOR_END, version[version_sorted[j]], COL_VER, WHITE)         ;       # Version
                                        printf(COLOR_BEGIN WHITE "%6s" COLOR_END"|"," ("oh_list[oh[version_sorted[j]]] ") ")            ;       # OH id

					if (length(INT_DB_SVC) > 2)
					{	if (length(tab_svc_db[version_sorted[j]]) > 0)                # We print only if we have something to show
						{	printf("%s", center(tab_svc_db[version_sorted[j]], COL_SVC, WHITE));
						} else {
							printf("%s", center("", COL_SVC, WHITE));
						}
					}

                                        for (i = 1; i <= n; i++) {
                                                dbstatus = status[version_sorted[j],nodes[i]]                    ;

                                                sub(",HOME=.*$", "", dbstatus)                                   ;       # Manage the 12cR2 new feature, check 20170606 for more details
                                                sub("),.*$", ")", dbstatus)                                      ;       # To make clear multi status like "Mounted (Closed),Readonly,Open Initiated"

                                                #
                                                # Print the status here, all that are not listed in that if ladder will appear in RED
                                                #
                                                if (dbstatus == "")                     {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Open")                 {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}      else
                                                if (dbstatus == "Started" && dbtype[version_sorted[j]] == "ASM") {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}      else
                                                if (dbstatus == "Open,Readonly")        {printf("%s", center(dbstatus, COL_NODE, WHITE        ))      ;}      else
                                                if (dbstatus == "Readonly")             {printf("%s", center(dbstatus, COL_NODE, YELLOW       ))      ;}      else
                                                if (dbstatus == "Instance Shutdown")    {printf("%s", center(dbstatus, COL_NODE, YELLOW       ))      ;}      else
                                                                                        {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        #
                                        # Color the DB Type column depending on the ROLE of the database (20170619)
                                        #
                                        if (role[version_sorted[j]] == "PRIMARY") { ROLE_COLOR=WHITE ; ROLE_SHORT=" (P)"; } else { ROLE_COLOR=RED ; ROLE_SHORT=" (S)" }
                                        printf("%s", center(dbtype[version_sorted[j]] ROLE_SHORT, COL_TYPE, ROLE_COLOR))           ;

                                        printf("\n")                                                              ;
                                }

                                # a "---" line as a footer
                                print_a_line()                                                                    ;

                                #
                                # Print the OH list and a legend for the DB Type colors underneath the table
                                #
                                printf ("\n\t%s", "ORACLE_HOME references listed in the Version column :")        ;

                                # Print the output in many lines for code visibility
                                #printf ("\t\t%s\t", "DB Type column =>")                                         ;       # Most likely useless
                                printf ("\t\t\t\t\t")                                                             ;
                                printf("%s" COLOR_BEGIN WHITE "%-6s" COLOR_END    , "Primary : ", "White")        ;
                                printf("%s" COLOR_BEGIN WHITE "%s"   COLOR_END"\n", "and "      , "(P)"  )        ;
                                printf ("\t\t\t\t\t\t\t\t\t\t\t\t")                                               ;
                                printf("%s" COLOR_BEGIN RED "%-6s"   COLOR_END    , "Standby : ", "Red"  )        ;
                                printf("%s" COLOR_BEGIN RED "%s"     COLOR_END"\n", "and "      , "(S)" )         ;


                                for (x in oh_list)
                                {
                                        printf("\t\t%s\n", oh_list[x] " : " x) | "sort"                           ;
                                }
	
				for (db in tab_svc_db)
				{
					split(tab_svc_db[db], services, ",");
					for (svc in services)
					{
						alias2[services[svc]] = alias2[db];
					}
				}

				for (id in alias)
				{
					printf("alias -- %s=\"export ORACLE_SID=%s;export ORACLE_HOME=%s;export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH;export SHLIB_PATH=$BASE_SHLIB_PATH:$ORACLE_HOME/bin:$ORACLE_HOME/lib;echo \\\"ORACLE_SID = %s\nORACLE_HOME = %s\\\"\"\n", id, id, alias[id], id, alias[id]) > FILENAME "a" ;
				}

                                for (id in alias2)
                                {
					printf("alias -- %s=%s\n",id, alias2[id]) > FILENAME "a"		;
                                }
                        }
        }' $TMP

	if [[ $SET_ALIAS = 'YES' ]]; then
		source ${TMP}a						;
	fi
        printf "\n"

if [ -f ${TMP} ]
then
	rm -f ${TMP}
fi

if [ -f ${TMP}a ]
then
	rm -f ${TMP}a
fi

#*********************************************************************************************************
#                               E N D     O F      S O U R C E
#*********************************************************************************************************


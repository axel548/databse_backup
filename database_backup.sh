#!/bin/bash
# Shell script para obtener  una copia desde mysql
# Desarrollado por ax_of_war

set -e
# si sucede un error, se deja de ejecutar.

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename $0)"
readonly BACKUP_LOG_FILENAME="database_backup.log"

function end_script_execution() {
	echo "----------------------------------" >> $BACKUP_LOG_FILENAME
	echo "Terminando la ejecución del script" >> $BACKUP_LOG_FILENAME 
	echo "----------------------------------" >> $BACKUP_LOG_FILENAME
	echo "" >> $BACKUP_LOG_FILENAME
}

function end_script_execution_with_error() {
	end_script_execution
	exit 1
}

function validate_env_variables() {
	
	local FLAG=true

	if [ -z "$DB_BCKP_USER" ]; then 
		log_error "No se  ha definido una variable de entorno con el usuario de la base de datos"
		FLAG=false
	fi

	if [ -z "$DB_BCKP_PASS" ]; then 
		log_error "No se  ha definido una variable de entorno con la contraseña de la base de datos"
		FLAG=false
	fi

	if [ -z "$DB_BCKP_HOST" ]; then 
		log_error "No se  ha definido una variable de entorno con el host de la base de datos"
		FLAG=false
	fi

	if [ -z "$DB_BCKP_DATABASE" ]; then 
		log_error "No se  ha definido una variable de entorno con el nombre de la base de datos"
		FLAG=false
	fi

	if [ -z "$DB_BCKP_BUCKET" ]; then 
		log_error "No se  ha definido una variable de entorno con el nombre del bucket de Amazon S3 para hacer el backup."
		FLAG=false
	fi

	if [ "$FLAG" = false ]; then 
		end_script_execution_with_error
	fi
}

function log_error() {
	log "ERROR" "$1"
}

function log_info() {
	log "INFO" "$1"
}

function log() {
	local readonly level=$1
	local readonly message=$2
	local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S") #2020-12-25 00:00:00

	echo "${timestamp} [${level}] [$SCRIPT_NAME] $message" >> $BACKUP_LOG_FILENAME
}

function assert_is_installed() {
	local readonly name=$1
	
	if [[ ! $(command -v $name) ]]; then
		log_error "El binario '$name' es requerido pero no está instalado"	
		end_script_execution_with_error
	fi
}

function validate_installed_binaries(){
	assert_is_installed "mysql"
	assert_is_installed "mysqldump"
	assert_is_installed "gzip"
	assert_is_installed "aws"
}

function check_files() {
	local readonly BUCKET=$1
	
	#Listo todos los archivos que hay en el bucket, al resultado le hago split de espacios en blanco y obtengo la posición 4 (El nombre del archivo), a este resultado le hago otro split a través del caracter "/" para obtener unicamente el nombre

	local readonly ALL_AMAZON_BACKUPS="$(aws s3 ls s3://$BUCKET --recursive | awk '{print $4}' | awk -F/ 'print $NF')"
	local readonly NUMBER_OF_BACKUPS="$(echo "$ALL_AMAZON_BACKUPS" | wc -l )"

	log_info "Encontrados ${NUMBER_OF_BACKUPS} archivos almacenados en S3"

	#Si hay más de 6 archivos, empezamos a elminar los  archivos viejos, 6 porque al escribir el nuevo archivo será el archivo número 7
	if [[ $NUMBER_OF_BACKUPS -gt 6 ]]; then
		local readonly OLDER_FILE="$(echo "$ALL_AMAZON_BACKUPS" | sort | head -n 1)"
		log_info "Archivo más viejo $OLDER_FILE"
		aws s3 rm "s3://$BUCKET/$OLDER_FILE"
		log_info "Eliminado de s3: $OLDER_FILE"
	fi
}

function make_backup() {
	local readonly BAK=$(echo $HOME/mysql)
	local readonly MYSQL=$(which mysql)	
	local readonly MYSQLDUMP=$(which mysqldump)
	local readonly GZIP=$(which gzip)
	local readonly NOW=$(date +"%d-%m-%Y-%H_%M_%S")

	local readonly USER=$DB_BCKP_USER
	local readonly PASS=$DB_BCKP_PASS
	local readonly HOST=$DB_BCKP_HOST
	local readonly DATABASE=$DB_BCKP_DATABASE
	local readonly BUCKET=$DB_BCKP_BUCKET/$DATABASE
	
	log_info "Empezando la copia de seguridad para la base de datos $DATABASE en el bucket $BUCKET"
	
	[ ! -d $BAK ] && mkdir -p $BAK

	FILENAME="$DATABASE-$NOW.gz"
	# backup-2021-04-21-00_00_00.gz
	
	FILE=$BAK/$FILENAME 
	
	$MYSQLDUMP -u $USER -h $HOST -p $PASS $DATABASE | $GZIP -9 > $FILE
	
	#creamos los archivos para ver si hay más de 7 y elimina el más viejo
	check_files $BUCKET
	
	#Subimos el nuevo backup que acabamos de crear
	log_info "Empezando la subida a s3"
	aws s3 cp $BAK/$FILENAME s3://$BUCKET/$FILENAME

	#Eliminamos el archivo de este servidor
	log_info "Eliminando el archivo de este servidor"
	rm $FILE
}

echo "--------------------------" >> $BACKUP_LOG_FILENAME
echo "Ejecutando el script" >> $BACKUP_LOG_FILENAME 
echo "--------------------------" >> $BACKUP_LOG_FILENAME

validate_env_variables 
validate_installed_binaries
make_backup
en_script_execution

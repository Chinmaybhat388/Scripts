#Script to dynamically read the superuser password from vault and perform a logical backup of a postgresql database. 

import hvac
from cryptography.fernet import Fernet
import warnings
import subprocess
import os
from datetime import datetime

warnings.filterwarnings("ignore", category=DeprecationWarning)

key = os.getenv('encryption_key')
role_id = 'gAAAAABn0_CB19O3aytVbnN9wP_PEMtG9YpYlC-VTWfHEYIBPuNdrBjbo6dbyDjogcT6JyVa7KrgPkPue8gnpRf1e2nYzkGkptGJASZd3np4Hco5LMk2G5YU46cIEHHRKXeWQxtsnUCx'
secret_id = 'gAAAAABn0_CGWcfo9QKZY6LghUEL2JQSTWAMnKUMvs9s-F9haGBe1CygtsTV25_Db1mq-N1-p6FJP5dlbd4Bb_N6QowCN3hQHcT_Qiu5AUNFJzp9lJAQj12jE8r8h7WI7DgR8V0O52bT'

fernet = Fernet(key)
decrypted_role_id = fernet.decrypt(role_id).decode()
decrypted_secret_id = fernet.decrypt(secret_id).decode()

try:
    # Initialize the client
    client = hvac.Client(url='https://onevault.npe.company.com:8200')

    # Authenticate with Vault using AppRole
    client.auth.approle.login(decrypted_role_id, decrypted_secret_id)

    if client.is_authenticated():
        # Read the password from Vault
        read_pw = client.secrets.kv.read_secret_version(mount_point='secrets/', path='postgres/auth-creds')
        username = read_pw['data']['data']['username']
        password = read_pw['data']['data']['password']
        print("Password fetched from vault")

        os.environ['PGPASSWORD'] = password

        current_time = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

        backup_file = f'/postgres_dump/dbbackup/pg_dump/pg_dump-msb-{current_time}.bkp'

        backup_command = ['pg_dump', '-p', '50001', '-Fc', '-Z9', '-b',  '-C', '-U', 'postgres', '-d', 'msb', '-f', backup_file]
        result = subprocess.run(backup_command)

        if result.returncode == 0:
            print("Backup completed successfully")
        else:
            print(f"Backup failed with return code: {result.returncode}")
    else:
        print("Authentication failed.")

except Exception as e:
    print(f"Authentication to Vault failed. Failed to get Postgres password from Vault: {e}")

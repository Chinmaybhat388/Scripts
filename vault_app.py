import hvac
import psycopg2
import tempfile
import os
import warnings

warnings.filterwarnings("ignore", category=UserWarning, module="urllib3")

# Vault & PostgreSQL config
VAULT_ADDR = "https://xxxxx-npe.xxx.com:8200"
ROLE_ID = "xxxxxxxx-7811-xxxx-xxxx-20d000xx0fef"
SECRET_ID = "xxxxxxxx-xxxx-aa64-xxxx-bf35xxx23887"
DB_VAULT_ROLE_CREATE = "test_static_postgresql"
DB_VAULT_ROLE_INSERT = "test_static_postgresql_vltappuser"

DB_HOST = "vltpostgrestst.xxxx-postgres-dev01.xxxxxx.xxxxx.com"
DB_PORT = 3854
DB_NAME = "vltpostgrestst"

def get_vault_client(vault_addr, role_id, secret_id):
    client = hvac.Client(url=vault_addr)
    client.auth.approle.login(role_id=role_id, secret_id=secret_id)
    if not client.is_authenticated():
        raise Exception("Vault authentication failed.")
    print("Authenticated with Vault.")
    return client

def fetch_db_credentials(client, db_role):
    creds = client.secrets.database.get_static_credentials(
        name=db_role,
        mount_point='database'
    )
    return creds["data"]

def fetch_and_mount_certs(client):
    # Fetch certs from Vault KV (Replace the path with your secret paths containing the certificate files for your db instance)
    sslcert = client.secrets.kv.v2.read_secret_version(mount_point='secrets/', path='postgres/poc/vltpostgrestst/dev/certs', raise_on_deleted_version=True)['data']['data']['sslcert']
    sslkey = client.secrets.kv.v2.read_secret_version(mount_point='secrets/', path='postgres/poc/vltpostgrestst/dev/certs', raise_on_deleted_version=True)['data']['data']['sslkey']
    sslrootcert = client.secrets.kv.v2.read_secret_version(mount_point='secrets/', path='postgres/poc/vltpostgrestst/dev/certs', raise_on_deleted_version=True)['data']['data']['sslrootcert']

    # Save to temporary files
    sslcert_file = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.crt')
    sslkey_file = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.key')
    sslrootcert_file = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.crt')

    sslcert_file.write(sslcert)
    sslkey_file.write(sslkey)
    sslrootcert_file.write(sslrootcert)

    sslcert_file.close()
    sslkey_file.close()
    sslrootcert_file.close()

    return sslcert_file.name, sslkey_file.name, sslrootcert_file.name

def connect_postgres(host, port, dbname, username, password, sslcert, sslkey, sslrootcert):
    return psycopg2.connect(
        host=host,
        port=port,
        dbname=dbname,
        user=username,
        password=password,
        sslmode='verify-ca',
        sslcert=sslcert,
        sslkey=sslkey,
        sslrootcert=sslrootcert
    )

def statement_parser(query):
    statement_type=query.lower().split()[0]
    
    if statement_type == "select" or statement_type == "insert" or statement_type == "update" or statement_type == "delete":
        return "DML"
    elif statement_type == "create" or statement_type == "drop":
        return "DDL"
    else:
        return "Not a valid SQL query."

try:
    dbclient = get_vault_client(VAULT_ADDR, ROLE_ID, SECRET_ID)
    admin_user_creds = fetch_db_credentials(dbclient, DB_VAULT_ROLE_CREATE)
    app_user_creds = fetch_db_credentials(dbclient, DB_VAULT_ROLE_INSERT)
    cert_path , key_path , ca_path = fetch_and_mount_certs(dbclient)
    #print("Admin user password is : ", admin_user_creds["password"])
    #print("App user password is: ", app_user_creds["password"])

    query = input("Enter your query : ")

    transaction_type = statement_parser(query)
    if transaction_type == "DML" or transaction_type == "DDL":
        print("Your transaction type is ",transaction_type)
    else:
        print("Your transaction type is not relevant.")

    if transaction_type == "DML":
        db_connection = connect_postgres(DB_HOST, DB_PORT, DB_NAME, app_user_creds["username"], app_user_creds["password"], cert_path, key_path, ca_path)
        print("Executing :", query)
        with db_connection.cursor() as cur:
            cur.execute(query)
            if query.lower().split()[0] == "select":
                rows = cur.fetchall()
                for row in rows:
                    print(row)

            db_connection.commit()
            db_connection.close()
            print(f"{query.lower().split()[0]} completed.")

    elif transaction_type == "DDL":
        db_connection = connect_postgres(DB_HOST, DB_PORT, DB_NAME, admin_user_creds["username"], admin_user_creds["password"], cert_path, key_path, ca_path)
        print("Executing :", query)
        with db_connection.cursor() as cur:
            cur.execute(query)
            db_connection.commit()
            db_connection.close()
            print(f"{query.lower().split()[0]} completed.")
    else:
        print(f"{transaction_type}")
    

except Exception as e:
    print("Unable to fetch password.")

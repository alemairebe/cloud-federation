import os
import requests
import json
import boto3
from azure.identity import ClientAssertionCredential
from azure.identity import WorkloadIdentityCredential
from datetime import datetime, timedelta
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.storage.blob import generate_container_sas, ContainerSasPermissions

# Azure variables
AZURE_TENANT_ID = os.environ["AZURE_TENANT_ID"]
AZURE_CLIENT_ID = os.environ["AZURE_CLIENT_ID"]
account_name = os.environ["AZURE_STORAGE_ACCOUNT_NAME"]
container_name = os.environ["AZURE_STORAGE_CONTAINER_NAME"]



# Cognito variables
COGNITO_IDENTITY_POOL_ID = os.environ["COGNITO_IDENTITY_POOL_ID"]
COGNITO_DEV_PROVIDER_NAME = os.environ["COGNITO_DEV_PROVIDER_NAME"]

secret_name = os.environ.get("SAS_SECRET_NAME", "azure_blob_sas_token")

# GCP variables
# GCP_FUNCTION_URL = os.environ["GCP_FUNCTION_URL"]

def get_cognito_oidc_token():
    cognito_client = boto3.client('cognito-identity')
    response = cognito_client.get_open_id_token_for_developer_identity(
        IdentityPoolId=COGNITO_IDENTITY_POOL_ID,
        Logins={COGNITO_DEV_PROVIDER_NAME: lambda_arn},
        TokenDuration=900
    )
    print(f"{json.dumps(response)}")
    return response['Token']

def generate_blob_sas_token(account_name, container_name):
        azure_client = ClientAssertionCredential(
            tenant_id=AZURE_TENANT_ID,
            client_id=AZURE_CLIENT_ID,
            func=get_cognito_oidc_token
        )
        print("Obtained Azure Client Assertion Credential.")
        account_url = f"https://{account_name}.blob.core.windows.net"
        
        # Create service client with the AAD credential and request a user delegation key valid for 30 days
        bsc = BlobServiceClient(account_url=account_url, credential=azure_client)
        print("Created BlobServiceClient.")
        start = datetime.utcnow()
        expiry = start + timedelta(days=30)
        user_delegation_key = bsc.get_user_delegation_key(start, expiry)
        print("Obtained User Delegation Key.")
        # Generate a user-delegation SAS for the container (allows access to any blob in the container) valid for 30 days
        sas_token = generate_blob_sas(
            account_name=account_name,
            container_name=container_name,
            # omit blob_name to create a container-level SAS (applies to any blob)
            user_delegation_key=user_delegation_key,
            permission=BlobSasPermissions(read=True, list=True),
            start=start,
            expiry=expiry
        )
        return sas_token

def get_blob_sas_token(account_name, container_name):
        azure_client = WorkloadIdentityCredential(
            tenant_id=AZURE_TENANT_ID,
            client_id=AZURE_CLIENT_ID,
            token_file_path="/tmp/token.txt"
        )
        print("Obtained Azure Client Assertion Credential.")
        account_url = f"https://{account_name}.blob.core.windows.net"
        
        # Create service client with the AAD credential and request a user delegation key valid for 30 days
        bsc = BlobServiceClient(account_url=account_url, credential=azure_client)
        print("Created BlobServiceClient.")
        start = datetime.utcnow()
        delegation_end = start + timedelta(days=1)
        expiry = start + timedelta(days=30)
        # User delegation key is needed to sign SAS and is valid for max 7 days
        user_delegation_key = bsc.get_user_delegation_key(start, delegation_end)
        print("Obtained User Delegation Key.")
        # Generate a user-delegation SAS for the container (allows access to any blob in the container) valid for 30 days
        # Sign the container-level SAS using the user_delegation_key (AAD user delegation) instead of the account key.
        # The generate_container_sas call below receives user_delegation_key and will produce a container-scoped SAS.
        sas_token = generate_container_sas(
            account_name=account_name,
            container_name=container_name,
            user_delegation_key=user_delegation_key,
            permission=ContainerSasPermissions(read=True, list=True),
            start=start,
            expiry=expiry
        )
        return sas_token

def store_sas_token_in_secret_manager(sas_token):
    """
    Store or update the SAS token in AWS Secrets Manager.
    Uses env var SAS_SECRET_NAME (default: 'azure_blob_sas_token').
    Returns the secret ARN or raises on error.
    """
    r
    # return ARN if present, otherwise return Name
    return resp.get("ARN") or resp.get("Name")


def lambda_handler(event, context):
    global lambda_arn
    lambda_arn = context.invoked_function_arn
    # ----- STEP 1: Call Azure Function -----
    try:
        with open("/tmp/token.txt", "w") as f:
            f.write(get_cognito_oidc_token())
        print("Cognito OIDC token written to /tmp/token.txt")
    except Exception as e:
        print(f"Error obtaining Cognito OIDC token: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": f"Cognito OIDC Token Error: {str(e)}"})}
    try:
        sas_token = get_blob_sas_token(account_name, container_name)
        print("SAS Token generated.")
        sm = boto3.client("secretsmanager")
        print(f"Current SAS token in Secrets Manager: {sm.get_secret_value(SecretId=secret_name)}")

        # Store SAS token in Secrets Manager
        resp = sm.update_secret(SecretId=secret_name, SecretString=sas_token)

        print(f"SAS token stored in Secrets Manager: {resp.get('ARN')}")

        result = {
            "sas_secret_arn": resp.get("ARN"),
            "sas_token": sas_token
        }
    except Exception as e:
        print(f"Error during orchestration: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": f"Orchestration Error: {str(e)}"})}

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Cross-cloud orchestration successful!",
            "retrievedUserData": result
        })
    }

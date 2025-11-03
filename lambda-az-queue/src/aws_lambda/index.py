import os
import requests
import json
import boto3
from google.auth import default
from google.auth.transport.requests import Request
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient

# Azure variables
AZURE_TENANT_ID = os.environ["AZURE_TENANT_ID"]
AZURE_CLIENT_ID = os.environ["AZURE_CLIENT_ID"]
AZURE_FUNCTION_URL = os.environ["AZURE_FUNCTION_URL"]
AZURE_API_SCOPE = os.environ["AZURE_API_SCOPE"] # This will now be "api://multicloud-api/.default"

# Cognito variables
COGNITO_IDENTITY_POOL_ID = os.environ["COGNITO_IDENTITY_POOL_ID"]
COGNITO_DEV_PROVIDER_NAME = os.environ["COGNITO_DEV_PROVIDER_NAME"]

# GCP variables
# GCP_FUNCTION_URL = os.environ["GCP_FUNCTION_URL"]

def get_cognito_oidc_token(lambda_function_arn):
    cognito_client = boto3.client('cognito-identity')
    response = cognito_client.get_open_id_token_for_developer_identity(
        IdentityPoolId=COGNITO_IDENTITY_POOL_ID,
        Logins={COGNITO_DEV_PROVIDER_NAME: lambda_function_arn},
        TokenDuration=900
    )
    return response['Token']

def exchange_token_for_azure_access_token(cognito_jwt):
    """Exchange Cognito OIDC token for Azure AD access token using workload identity federation."""
    token_endpoint = f"https://login.microsoftonline.com/{AZURE_TENANT_ID}/oauth2/v2.0/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": AZURE_CLIENT_ID,
        "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion": cognito_jwt,
        "scope": AZURE_API_SCOPE
    }
    resp = requests.post(token_endpoint, data=data)
    if resp.status_code != 200:
        print(f"Azure AD token exchange failed: {resp.status_code} {resp.text}")
        raise Exception(f"Azure AD token exchange failed: {resp.status_code} {resp.text}")
    return resp.json()["access_token"]

def call_azure_function(access_token, email):
    """Call the Azure Function with the Azure AD access token."""
    headers = {"Authorization": f"Bearer {access_token}"}
    params = {"email": email}
    resp = requests.get(AZURE_FUNCTION_URL, headers=headers, params=params)
    if resp.status_code != 200:
        print(f"Azure Function call failed: {resp.status_code} {resp.text}")
        raise Exception(f"Azure Function call failed: {resp.status_code} {resp.text}")
    return resp.json()

def copy_blob_to_s3():
        # Set up Azure credential (uses environment variables for federated identity)
    credential = DefaultAzureCredential()

    # Blob details from environment or event
    account_url = f"https://{os.environ['AZURE_STORAGE_ACCOUNT']}.blob.core.windows.net"
    container = os.environ.get("AZURE_STORAGE_CONTAINER", "$web")
    blob_name = os.environ.get("AZURE_STORAGE_BLOB", "azure_function.zip")
    s3_bucket = os.environ["S3_BUCKET_NAME"]
    s3_key = blob_name

    # Download blob
    blob_client = BlobClient(account_url, container, blob_name, credential=credential)
    downloader = blob_client.download_blob()
    blob_bytes = downloader.readall()

    # Upload to S3
    s3 = boto3.client("s3")
    s3.put_object(Bucket=s3_bucket, Key=s3_key, Body=blob_bytes)

    return {"statusCode": 200, "body": f"Blob {blob_name} copied to S3 bucket {s3_bucket}."}



def get_gcp_identity_token():
    print("Attempting to get GCP identity token...")
    # google-auth library handles the AWS->GCP federation automatically
    credentials, _ = default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    credentials.refresh(Request())
    
    # We need an OIDC Identity Token to call the Cloud Function
    identity_creds = default(target_audience=GCP_FUNCTION_URL)[0]
    identity_creds.refresh(Request())
    print("Successfully acquired GCP identity token.")
    return identity_creds.token
    
def lambda_handler(event, context):
    email_to_lookup = event.get("email")
    if not email_to_lookup:
        return {"statusCode": 400, "body": json.dumps({"error": "Email not provided."})}

    # ----- STEP 1: Call Azure Function -----
    # try:
    #     # We pass the Lambda's own ARN as the unique LoginId for Cognito
    #     azure_token = get_azure_token(context.invoked_function_arn)
    #     headers = {'Authorization': f'Bearer {azure_token}'}
    #     params = {'email': email_to_lookup}
    #     response = requests.get(AZURE_FUNCTION_URL, headers=headers, params=params)
    #     response.raise_for_status()
    #     user_id = response.json().get("userId")
    #     print(f"Successfully retrieved userId: {user_id} from Azure.")
    # except Exception as e:
    #     print(f"Error calling Azure: {e}")
    #     return {"statusCode": 500, "body": json.dumps({"error": f"Azure Error: {str(e)}"}) }


    # ----- STEP 1: Call Azure Function -----
    try:
        cognito_jwt = get_cognito_oidc_token(context.invoked_function_arn)
        print(f"{json.dumps(cognito_jwt)}")
        # 2. Exchange for Azure AD access token
        azure_token = exchange_token_for_azure_access_token(cognito_jwt)
        print(f"{json.dumps(azure_token)}")
        # 3. Call Azure Function
        result = call_azure_function(azure_token, email_to_lookup)
        print(f"{json.dumps(result)}")
    except Exception as e:
        print(f"Error calling Azure: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": f"Azure Error: {str(e)}"}) }


    # ----- STEP 2: Call GCP Function -----
    # try:
    #     gcp_token = get_gcp_identity_token()
    #     headers = {
    #         'Authorization': f'Bearer {gcp_token}',
    #         'Content-Type': 'application/json'
    #     }
    #     payload = {'userId': user_id}
    #     response = requests.post(GCP_FUNCTION_URL, headers=headers, json=payload)
    #     response.raise_for_status()
    #     user_data = response.json()
    #     print(f"Successfully retrieved data from GCP: {user_data}")
    # except Exception as e:
    #     print(f"Error calling GCP: {e}")
    #     return {"statusCode": 500, "body": json.dumps({"error": f"GCP Error: {str(e)}"}) }

    # return {
    #     "statusCode": 200,
    #     "body": json.dumps({
    #         "message": "Cross-cloud orchestration successful!",
    #         "retrievedUserData": user_data
    #     })
    # }
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Cross-cloud orchestration successful!",
            "retrievedUserData": result
        })
    }

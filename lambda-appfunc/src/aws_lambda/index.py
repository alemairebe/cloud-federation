import os
import requests
import json
import boto3

# Azure variables
AZURE_TENANT_ID = os.environ["AZURE_TENANT_ID"]
AZURE_CLIENT_ID = os.environ["AZURE_CLIENT_ID"]
AZURE_FUNCTION_URL = os.environ["AZURE_FUNCTION_URL"]
AZURE_AUDIENCE = os.environ["AZURE_AUDIENCE"]
AZURE_API_SCOPE = os.environ["AZURE_API_SCOPE"] # This will now be "api://multicloud-api/.default"

# Cognito variables
COGNITO_IDENTITY_POOL_ID = os.environ["COGNITO_IDENTITY_POOL_ID"]
COGNITO_DEV_PROVIDER_NAME = os.environ["COGNITO_DEV_PROVIDER_NAME"]
AWS_USE_STS = os.environ.get("AWS_USE_STS", "false").lower() == "true"

def get_cognito_oidc_token(lambda_function_arn):
    cognito_client = boto3.client('cognito-identity')
    response = cognito_client.get_open_id_token_for_developer_identity(
        IdentityPoolId=COGNITO_IDENTITY_POOL_ID,
        Logins={COGNITO_DEV_PROVIDER_NAME: lambda_function_arn},
        TokenDuration=900
    )
    return response['Token']

def get_sts_outbound_federation_token():
    sts_client = boto3.client('sts')
    response = sts_client.get_web_identity_token(
    Audience=[AZURE_AUDIENCE],
    SigningAlgorithm='ES384',
    DurationSeconds=300
    )
    return response['WebIdentityToken']

def exchange_token_for_azure_access_token(aws_jwt):
    """Exchange Cognito OIDC token for Azure AD access token using workload identity federation."""
    token_endpoint = f"https://login.microsoftonline.com/{AZURE_TENANT_ID}/oauth2/v2.0/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": AZURE_CLIENT_ID,
        "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion": aws_jwt,
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
    
def lambda_handler(event, context):
    email_to_lookup = event.get("email")
    if not email_to_lookup:
        return {"statusCode": 400, "body": json.dumps({"error": "Email not provided."})}

    try:
        if AWS_USE_STS:
            aws_jwt = get_sts_outbound_federation_token()
        else:
            aws_jwt = get_cognito_oidc_token(context.invoked_function_arn)
        print(f"{json.dumps(aws_jwt)}")
        # 2. Exchange for Azure AD access token
        azure_token = exchange_token_for_azure_access_token(cognito_jwt)
        print(f"{json.dumps(azure_token)}")
        # 3. Call Azure Function
        result = call_azure_function(azure_token, email_to_lookup)
        print(f"{json.dumps(result)}")
    except Exception as e:
        print(f"Error calling Azure: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": f"Azure Error: {str(e)}"}) }

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Cross-cloud orchestration successful!",
            "retrievedUserData": result
        })
    }

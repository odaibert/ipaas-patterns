# Shared utilities for iPaaS Patterns labs
# Inspired by Azure-Samples/AI-Gateway

import subprocess
import json
import datetime
from dataclasses import dataclass
from typing import Optional

# ANSI color codes
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'

@dataclass
class CommandResult:
    """Result of a command execution"""
    success: bool
    output: str
    json_data: Optional[dict] = None

def print_info(message: str):
    """Print info message in blue"""
    print(f"{Colors.BLUE}ℹ️  {message}{Colors.RESET}")

def print_success(message: str):
    """Print success message in green"""
    print(f"{Colors.GREEN}✅ {message}{Colors.RESET}")

def print_error(message: str):
    """Print error message in red"""
    print(f"{Colors.RED}❌ {message}{Colors.RESET}")

def print_warning(message: str):
    """Print warning message in yellow"""
    print(f"{Colors.YELLOW}⚠️  {message}{Colors.RESET}")

def run(command: str, success_message: str = None, error_message: str = None) -> CommandResult:
    """
    Execute a shell command and return the result
    
    Args:
        command: The command to execute
        success_message: Message to print on success
        error_message: Message to print on error
    
    Returns:
        CommandResult with success status, output, and parsed JSON if applicable
    """
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True
        )
        
        output = result.stdout.strip() if result.stdout else result.stderr.strip()
        success = result.returncode == 0
        
        json_data = None
        if success and output:
            try:
                json_data = json.loads(output)
            except json.JSONDecodeError:
                pass
        
        if success and success_message:
            print_success(f"{success_message} ⌚ {datetime.datetime.now().strftime('%H:%M:%S')}")
        elif not success and error_message:
            print_error(f"{error_message}: {output}")
        
        return CommandResult(success=success, output=output, json_data=json_data)
    
    except Exception as e:
        if error_message:
            print_error(f"{error_message}: {str(e)}")
        return CommandResult(success=False, output=str(e))

def get_current_subscription() -> Optional[str]:
    """Get the current Azure subscription ID"""
    try:
        result = run("az account show", "Retrieved Azure account", "Failed to get Azure account")
        
        if result.success and result.json_data:
            subscription_id = result.json_data['id']
            subscription_name = result.json_data['name']
            print_info(f"Using Subscription: {subscription_name} ({subscription_id})")
            return subscription_id
        else:
            print_error("No current subscription found.")
            return None
    except Exception as e:
        print_error(f"Error retrieving subscription: {e}")
        return None

def create_resource_group(name: str, location: str) -> bool:
    """
    Create an Azure resource group if it doesn't exist
    
    Args:
        name: Resource group name
        location: Azure region
    
    Returns:
        True if successful
    """
    # Check if exists
    check = run(f"az group exists --name {name}")
    
    if check.output.lower() == "true":
        print_info(f"Resource group '{name}' already exists")
        return True
    
    # Create
    result = run(
        f"az group create --name {name} --location {location}",
        f"Created resource group '{name}' in {location}",
        f"Failed to create resource group '{name}'"
    )
    
    return result.success

def deploy_bicep(resource_group: str, template_file: str, parameters: dict = None) -> Optional[dict]:
    """
    Deploy a Bicep template
    
    Args:
        resource_group: Target resource group
        template_file: Path to Bicep file
        parameters: Optional deployment parameters
    
    Returns:
        Deployment outputs if successful
    """
    cmd = f"az deployment group create --resource-group {resource_group} --template-file {template_file}"
    
    if parameters:
        params_str = " ".join([f"--parameters {k}={v}" for k, v in parameters.items()])
        cmd += f" {params_str}"
    
    cmd += " --query properties.outputs -o json"
    
    print_info(f"Deploying {template_file}...")
    result = run(cmd, "Deployment completed", "Deployment failed")
    
    return result.json_data if result.success else None

def get_deployment_outputs(resource_group: str, deployment_name: str = "main") -> Optional[dict]:
    """
    Get outputs from a deployment
    
    Args:
        resource_group: Resource group name
        deployment_name: Deployment name (default: main)
    
    Returns:
        Dictionary of outputs
    """
    result = run(
        f"az deployment group show --resource-group {resource_group} --name {deployment_name} --query properties.outputs -o json",
        "Retrieved deployment outputs",
        "Failed to get deployment outputs"
    )
    
    if result.success and result.json_data:
        # Flatten the outputs
        outputs = {}
        for key, value in result.json_data.items():
            outputs[key] = value.get('value')
        return outputs
    
    return None

def delete_resource_group(name: str, no_wait: bool = True) -> bool:
    """
    Delete an Azure resource group
    
    Args:
        name: Resource group name
        no_wait: Don't wait for completion
    
    Returns:
        True if deletion initiated successfully
    """
    wait_flag = "--no-wait" if no_wait else ""
    
    result = run(
        f"az group delete --name {name} --yes {wait_flag}",
        f"Initiated deletion of resource group '{name}'",
        f"Failed to delete resource group '{name}'"
    )
    
    return result.success

def test_api(url: str, method: str = "POST", headers: dict = None, body: dict = None) -> CommandResult:
    """
    Test an API endpoint
    
    Args:
        url: API endpoint URL
        method: HTTP method
        headers: Request headers
        body: Request body
    
    Returns:
        CommandResult with response
    """
    import requests
    
    try:
        response = requests.request(
            method=method,
            url=url,
            headers=headers,
            json=body,
            timeout=30
        )
        
        success = response.status_code < 400
        
        try:
            json_data = response.json()
        except:
            json_data = None
        
        return CommandResult(
            success=success,
            output=response.text,
            json_data=json_data
        )
    
    except Exception as e:
        return CommandResult(success=False, output=str(e))

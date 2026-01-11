#!/bin/bash
# Example script demonstrating how to use the Azure Data Explorer database listing tool

echo "=============================================================================="
echo "Azure Data Explorer Database Listing Tool - Usage Example"
echo "=============================================================================="
echo ""
echo "This script demonstrates how to use the tool to connect to Azure Data Explorer"
echo "and list all databases you have access to."
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "ERROR: Azure CLI is not installed."
    echo "Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

echo "✓ Azure CLI is installed"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed."
    echo "Please install Python 3 from: https://www.python.org/downloads/"
    exit 1
fi

echo "✓ Python 3 is installed"
echo ""

# Check if required Python packages are installed
echo "Checking Python dependencies..."
if ! python3 -c "import azure.kusto.data; import azure.identity" 2>/dev/null; then
    echo "Installing required Python packages..."
    pip install -q azure-kusto-data azure-identity
    if [ $? -eq 0 ]; then
        echo "✓ Python dependencies installed successfully"
    else
        echo "ERROR: Failed to install Python dependencies"
        exit 1
    fi
else
    echo "✓ Python dependencies are installed"
fi
echo ""

# Check if user is authenticated with Azure CLI
echo "Checking Azure CLI authentication..."
if az account show &> /dev/null; then
    echo "✓ You are authenticated with Azure CLI"
    echo ""
    echo "Current account:"
    az account show --query "{Subscription:name, ID:id, User:user.name}" -o table
    echo ""
else
    echo "⚠ You are not authenticated with Azure CLI"
    echo ""
    echo "To authenticate, run:"
    echo "  az login"
    echo ""
    echo "For device code authentication (useful in SSH/remote sessions):"
    echo "  az login --use-device-code"
    echo ""
    exit 1
fi

echo "=============================================================================="
echo "Running the database listing tool..."
echo "=============================================================================="
echo ""

# Run the script
python3 list_databases.py

exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
    echo "✓ Script completed successfully"
else
    echo "✗ Script failed with exit code $exit_code"
    echo ""
    echo "Common issues and solutions:"
    echo "  1. Not authenticated: Run 'az login'"
    echo "  2. No access to cluster: Contact your Azure administrator"
    echo "  3. Wrong cluster URL: Verify the cluster URL is correct"
fi

exit $exit_code

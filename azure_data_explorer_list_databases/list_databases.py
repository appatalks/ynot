#!/usr/bin/env python3
"""
Azure Data Explorer Database Listing Tool

This script connects to an Azure Data Explorer (Kusto) cluster and lists all
databases that the authenticated user has access to.

Requirements:
    - azure-kusto-data
    - azure-identity

Authentication:
    Uses Azure CLI credentials by default (run 'az login' first)
    Falls back to DefaultAzureCredential (managed identity, service principal, etc.)
"""

import sys
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
from azure.identity import AzureCliCredential, DefaultAzureCredential


def get_databases(cluster_url: str) -> list:
    """
    Connect to Azure Data Explorer cluster and retrieve list of databases.
    
    Args:
        cluster_url: The full URL of the ADX cluster
        
    Returns:
        List of database names
        
    Raises:
        Exception: If connection or query fails
    """
    try:
        # Try Azure CLI credentials first (most common for local development)
        print("Attempting authentication with Azure CLI credentials...")
        credential = AzureCliCredential()
        
        # Build connection string with AAD authentication
        kcsb = KustoConnectionStringBuilder.with_azure_token_credential(
            cluster_url,
            credential
        )
        
        # Create Kusto client
        client = KustoClient(kcsb)
        
        # Query to list all databases
        # .show databases returns: DatabaseName, PersistentStorage, Version, etc.
        query = ".show databases"
        
        print(f"Executing query: {query}")
        response = client.execute("", query)
        
        # Extract database names from the response
        databases = []
        for row in response.primary_results[0]:
            # The first column is typically the DatabaseName
            db_name = row[0]
            databases.append(db_name)
        
        return databases
        
    except Exception as e:
        print(f"Azure CLI authentication failed: {e}")
        print("Trying DefaultAzureCredential...")
        
        try:
            # Fall back to DefaultAzureCredential
            credential = DefaultAzureCredential()
            
            kcsb = KustoConnectionStringBuilder.with_azure_token_credential(
                cluster_url,
                credential
            )
            
            client = KustoClient(kcsb)
            query = ".show databases"
            
            print(f"Executing query: {query}")
            response = client.execute("", query)
            
            databases = []
            for row in response.primary_results[0]:
                db_name = row[0]
                databases.append(db_name)
            
            return databases
            
        except Exception as inner_e:
            print(f"DefaultAzureCredential authentication also failed: {inner_e}")
            raise


def main():
    """Main execution function."""
    # Azure Data Explorer cluster URL from the problem statement
    cluster_url = "https://kvc-k3qugk4g1mk0bzue1v.southcentralus.kusto.windows.net"
    
    print("=" * 80)
    print("Azure Data Explorer - Database Listing Tool")
    print("=" * 80)
    print(f"\nCluster URL: {cluster_url}")
    print("\nNote: Make sure you've authenticated with Azure CLI by running 'az login'\n")
    
    try:
        # Get list of databases
        databases = get_databases(cluster_url)
        
        # Display results
        print("\n" + "=" * 80)
        print(f"Successfully connected to cluster!")
        print(f"Found {len(databases)} database(s):")
        print("=" * 80)
        
        if databases:
            for i, db_name in enumerate(databases, 1):
                print(f"{i}. {db_name}")
        else:
            print("No databases found or no access to any databases.")
        
        print("\n" + "=" * 80)
        return 0
        
    except Exception as e:
        print("\n" + "=" * 80)
        print("ERROR: Failed to retrieve databases")
        print("=" * 80)
        print(f"\nError details: {e}")
        print("\nTroubleshooting:")
        print("1. Ensure you're authenticated: az login")
        print("2. Verify you have access to the cluster")
        print("3. Check that the cluster URL is correct")
        print("4. Ensure you have at least 'Database Viewer' role on the databases")
        print("\n" + "=" * 80)
        return 1


if __name__ == "__main__":
    sys.exit(main())

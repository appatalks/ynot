#!/usr/bin/env python3
"""
Test script to verify the Azure Data Explorer database listing tool structure
without requiring actual Azure authentication.

This validates:
- Import statements work
- Functions are properly defined
- Code structure is correct
"""

import sys
import os

# Add the parent directory to the path so we can import the module
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_imports():
    """Test that all required packages can be imported."""
    print("Testing imports...")
    try:
        from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
        from azure.identity import AzureCliCredential, DefaultAzureCredential
        print("✓ All required packages imported successfully")
        return True
    except ImportError as e:
        print(f"✗ Import error: {e}")
        return False


def test_module_structure():
    """Test that the module has the expected structure."""
    print("\nTesting module structure...")
    try:
        import list_databases
        
        # Check that required functions exist
        assert hasattr(list_databases, 'get_databases'), "Missing get_databases function"
        assert hasattr(list_databases, 'main'), "Missing main function"
        
        # Check that functions are callable
        assert callable(list_databases.get_databases), "get_databases is not callable"
        assert callable(list_databases.main), "main is not callable"
        
        print("✓ Module structure is correct")
        print("  - get_databases() function exists")
        print("  - main() function exists")
        return True
    except (ImportError, AssertionError) as e:
        print(f"✗ Module structure error: {e}")
        return False


def test_script_executable():
    """Test that the script is executable."""
    print("\nTesting script permissions...")
    script_path = os.path.join(os.path.dirname(__file__), 'list_databases.py')
    
    if os.access(script_path, os.X_OK):
        print("✓ Script is executable")
        return True
    else:
        print("⚠ Script is not executable (chmod +x list_databases.py)")
        return False


def main():
    """Run all tests."""
    print("=" * 80)
    print("Azure Data Explorer Database Listing Tool - Structure Tests")
    print("=" * 80)
    print()
    
    results = []
    results.append(test_imports())
    results.append(test_module_structure())
    results.append(test_script_executable())
    
    print("\n" + "=" * 80)
    if all(results):
        print("✓ All structure tests passed!")
        print("\nThe tool is ready to use. To run it:")
        print("  1. Authenticate with Azure CLI: az login")
        print("  2. Run the script: python list_databases.py")
    else:
        print("✗ Some tests failed. Please review the errors above.")
        return 1
    print("=" * 80)
    return 0


if __name__ == "__main__":
    sys.exit(main())

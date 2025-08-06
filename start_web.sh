#!/bin/bash

# Check if virtual environment exists, if not create it
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Upgrade pip to latest version
pip install --upgrade pip

# Install required packages in the virtual environment
echo "Installing required packages..."
pip install flask gunicorn

# Verify Flask installation
if ! python -c "import flask" &> /dev/null; then
    echo "Error: Flask installation failed"
    exit 1
fi

# Start the web application using Gunicorn
echo "Starting web application with Gunicorn..."
exec gunicorn --bind 0.0.0.0:5000 --workers 4 wsgi:app
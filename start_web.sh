#!/bin/bash

# Check if virtual environment exists, if not create it
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Check if gunicorn is installed, if not install it
if ! command -v gunicorn &> /dev/null
then
    echo "Installing Gunicorn..."
    pip install gunicorn
fi

# Install Flask if not already installed
if ! command -v flask &> /dev/null
then
    echo "Installing Flask..."
    pip install flask
fi

# Start the web application using Gunicorn
echo "Starting web application with Gunicorn..."
exec gunicorn --bind 0.0.0.0:5000 --workers 4 wsgi:app
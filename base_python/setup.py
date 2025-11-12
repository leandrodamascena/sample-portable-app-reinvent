from setuptools import setup, find_packages

setup(
    name="portable-aws-app-python",
    version="1.0.0",
    description="Portable application for Local Server, Docker, AWS Lambda, ECS and EKS - Python Version",
    author="Converted to Python",
    packages=find_packages(),
    install_requires=[
        "flask==3.0.0",
        "flask-cors==4.0.0",
        "pytest==7.4.3",
        "pytest-cov==4.0.0",
        "requests==2.31.0",
    ],
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
)

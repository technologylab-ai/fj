# Encrypted Git S3 Backup Guide

This is how I do it on my mac. Linux should be similar. Don't use Windows.

A complete guide to setting up a secure, client-side encrypted Git backup system using `git-remote-gcrypt` and AWS S3.

***

## Part 1: One-Time Machine & AWS Setup

Do these steps only once to prepare your computer and AWS account.


### 1. Install Software 💻

Use **Homebrew** and **pip** to install all command-line tools.

```bash
# Install GPG, gcrypt, and the AWS CLI with Homebrew
brew install gnupg git-remote-gcrypt awscli

# Install the S3 remote helper for Git with pip
pip3 install git-remote-s3
```

### 2. Create Your GPG Key 🔑

This is your personal master key that encrypts your backups.

```bash
# Start the key generation wizard
gpg --full-generate-key
```

Follow the prompts: choose **(1) RSA and RSA**, keysize **4096**, and **0** for expiration.

```bash
# List your keys to find your Key ID
gpg --list-secret-keys --keyid-format=long
```

**Securely back up this GPG key and its passphrase.** If you lose them, your backup is gone forever.

### 3. Configure GPG for macOS Prompts

This ensures GPG can properly ask for your passphrase.

```bash
# Install the native macOS prompter
brew install pinentry-mac

# Tell the GPG agent to use it
echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf

# Restart the agent to apply the change
gpgconf --kill gpg-agent
```

### 4. Set Up Your AWS S3 Bucket ☁️

Create a private bucket to store the encrypted data.
1.  Log in to the **AWS Console** and go to the **S3** service.
2.  **Create a bucket** with a globally unique name (e.g., `yourname-encrypted-git-backups`).
3.  Ensure **Block all public access** is checked.
4.  Under **Default encryption**, enable Server-side encryption and choose **SSE-S3**.

### 5. Create a Dedicated AWS IAM User 🤖

Create a programmatic user with restricted permissions.
1.  In the **IAM** service, create a new **User** (e.g., `git-backup-user`).
2.  For permissions, **Attach policies directly** and select the **`AmazonS3FullAccess`** policy.
3.  Finish creating the user.
4.  On the user's summary page, go to the **Security credentials** tab and **Create access key**.
5.  Select **Command Line Interface (CLI)** as the use case.
6.  **Immediately save the Access Key ID and Secret Access Key** to your password manager.

### 6. Configure the AWS CLI

Connect your machine to your new IAM user.

```bash
# Run the configuration wizard
aws configure
```

Paste the Access Key ID and Secret Access Key you just saved, and set your default region (e.g., `eu-central-1`). **Ensure your `~/.aws/credentials` and `~/.aws/config` files do not contain old profiles or expired session tokens.**

Verify the setup with `aws sts get-caller-identity`. This must return your user's details without errors.

***

## Part 2: New Repository Setup

Follow these steps for each new Git repository you want to back up.

### 1. Initialize Your Git Repository

If it's a new project, create a Git repository and make your first commit.

```bash
cd /path/to/your/project
git init
git add .
git commit -m "Initial commit"
```

### 2. Add the Encrypted S3 Remote

This command points Git to your S3 bucket.

```bash
# Replace the bucket name and the final path for your repo
git remote add origin gcrypt::s3://your-bucket-name/your-project-backup
```

### 3. Configure the GPG Participant

Tell `gcrypt` to encrypt the data using your personal GPG key.

```bash
# Replace with your actual GPG key ID from Part 1
git config gcrypt.participants YOUR_PERSONAL_GPG_KEY_ID
```

### 4. Perform the First Push

The first push to a new, empty remote initializes it and requires a special command.

```bash
# This creates the 'master' branch on the remote and links it
git push -u origin master
```

After this initial push, all future backups for this repository are simple:

```bash
git push
```

***

## Part 3: Setting Up for Automated Pushes (Optional, e.g. for fj serve)

Follow these steps if you need a web server or other automated script to be able to push to an existing encrypted repository.

### 1. Create a Passphrase-less GPG Key

This key will be used exclusively by your automation tool.

```bash
# Create the key non-interactively
gpg --batch --passphrase '' --quick-gen-key 'your-tool-automation@localhost'

# Get the new Key ID
gpg --list-secret-keys 'your-tool-automation@localhost'
```

### 2. Update the Repository's Trusted Participants

In your local clone of the repository, you must authorize this new key by adding it to the list of trusted participants. **You must include all trusted keys in one command.**

```bash
# Navigate to your local repository
cd /path/to/your/project

# 1. Clear any old, incorrect participant settings
git config --unset-all gcrypt.participants

# 2. Set the complete list of trusted keys: your personal key AND the new automation key
git config gcrypt.participants "YOUR_PERSONAL_KEY_ID YOUR_AUTOMATION_KEY_ID"
```

### 3. Configure the Repository for Automated Signing

Tell this specific repository (and only this one) to use the new automation key for signing its commits.

```bash
# This is a local setting for this repo only
git config user.signingkey YOUR_AUTOMATION_KEY_ID
```

### 4. Push the Authorization Update

You must now push from your terminal one last time. This push will be signed by your **personal key** (which `gpg-agent` will ask for) and will update the remote manifest to be encrypted for both keys.
```bash
# Make a small change, like editing a README file, then commit it
git add .
git commit -m "Authorize automation key"

# Push the update. You will be prompted for your personal GPG passphrase.
git push
```
After this push succeeds, your automated tool will be able to push to the repository using its dedicated, passphrase-less key without any prompts.


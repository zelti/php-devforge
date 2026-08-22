<p align="center">
  <img src="./logo.png" alt="PHP DevForge" width="300px" height="300px">
</p>

# PHP DevForge

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE) [![GitHub last commit](https://img.shields.io/github/last-commit/zelti/php-devforge)]()

A ready-to-use PHP development environment powered by Docker containers that provides automatic domain generation, local SSL certificates, and live code editing capabilities.

## 📖 Description

PHP DevForge is a comprehensive Docker-based development environment designed to streamline PHP development. It features:

- **Automatic Domain Generation**: Create local domains without manual configuration
- **Local SSL Certificates**: Auto-generated certificates with mkcert for secure HTTPS development
- **PHP Version Switching**: Switch between PHP versions via URL parameters
- **Live Code Editing**: Shared volumes allow real-time code changes
- **Multi-Container Setup**: Apache, PHP-FPM, DNS, and optional database services

The environment automatically generates URLs based on your project folder structure. For example, a project at `laravel/site/public/index.php` becomes accessible at `https://public--site--laravel.phpforge.dev`.

## 🔧 Installation

### 📋 Prerequisites

- Docker and Docker Compose (also used to generate the SSL certificates)
- Git
- Bash shell (Linux/macOS)

### 🚀 Setup Steps

1. **Clone the repository:**
   ```bash
   git clone git@github.com:zelti/php-devforge.git
   cd php-devforge
   ```
    Clone it wherever you like: the scripts and aliases resolve their own location.

2. **Run the installer:**
   ```bash
   ./install.sh
   ```
   It asks for your domain, where your projects should live and the default PHP
   version, finds a free DNS port, detects your user id, writes `.env`, creates the
   projects folder, and offers to generate the certificates and configure local DNS.

   Safe to re-run: your current `.env` supplies the defaults. For unattended use:
   ```bash
   ./install.sh --yes --domain=mydomain.dev --projects-dir=~/code
   ./install.sh --help        # every option
   ```

   Nothing needs `sudo` except the DNS step, and only if you accept it.

3. **Load the shortcuts (optional):**
   ```bash
   source aliases.bash
   ```
   Or add that line to your `~/.bashrc`, using the full path to this folder.

4. **Start the containers:**
    ```bash
    docker compose up -d
    ```
    (If you sourced the aliases, you can use `forge:start` instead)

    Check it works: `https://welcome--sites.phpforge.dev`

## 💻 Usage

### ▶️ Starting and Stopping

```bash
# Start all services
forge:start

# Stop all services
forge:stop

# Reload services
forge:reload

# Check current PHP version
forge:current

# Switch to PHP 8.3
forge:use:php83

# Switch to PHP 8.4
forge:use:php84

# Access PHP 8.3 container
forge:exec:php83

# Access PHP 8.4 container
forge:exec:php84

# View PHP 8.3 logs
forge:logs:php83

# View PHP 8.4 logs
forge:logs:php84
```

### 🌐 Accessing Your Projects

1. **Create project structure:**
   Your projects live in the folder you chose during install (`PROJECTS_DIR` in
   `.env`, `~/php-devforge` by default). The installer creates it with:

   ```
   ~/php-devforge/
   ├── projects/          your actual code
   └── sites/             one symlink per project, for shorter URLs
       └── welcome/       a test page
   ```

   Inside the containers this is always `/home/php-devforge/public_html`, which is
   where Apache and PHP look. Only the host side is configurable.

   **Symlinks must point inside `PROJECTS_DIR`.** The containers only see that
   folder, so a link to anywhere else resolves to nothing and returns 404.

   No `chown` is needed. The PHP containers adopt your user id at startup
   (`PUID`/`PGID` in `.env`), so files they create belong to you and `node_modules`
   can be deleted without `sudo`.

2. **URL Structure:**
   Projects are accessible via automatically generated URLs:
   - `folder/project/public/index.php` → `https://public--project--folder.phpforge.dev`
   - The URL is constructed by reversing the folder path segments separated by `--`

3. **PHP Version Switching:**
   Append `--p83` or `--p84` to the URL to use specific PHP versions:
   - `https://public--project--folder.phpforge.dev` (uses default PHP version)
   - `https://public--project--folder--p83.phpforge.dev` (forces PHP 8.3)
   - `https://public--project--folder--p84.phpforge.dev` (forces PHP 8.4)

### 🔄 Development Workflow

- Edit code in your IDE (files are volume-mounted for live updates)
- Changes appear immediately without restarting containers
- Use Xdebug for debugging (configure your IDE to listen on port **9003**, the Xdebug 3 default)
- Access PHP containers via `forge:exec:php84` (or `forge:exec:php83` for PHP 8.3)

## 🛠️ Supported PHP Extensions and Tools

### 📦 PHP Extensions
- **Core Extensions**: GD, Intl, Zip, PDO MySQL, PDO PostgreSQL, SOAP, XSL, BC Math, OPcache, Mbstring, Exif, PCNTL
- **PECL Extensions**: Imagick, Redis, APCu, Xdebug

### 🔨 Development Tools
- **Composer**: PHP dependency manager (pre-installed)
- **Node.js 19**: Via NVM (Node Version Manager)
- **Git**: Version control
- **Xdebug**: PHP debugging extension
- **Cron**: Task scheduling support

### 🐳 Container Features
- **User Setup**: devuser with sudo privileges
- **Volume Sharing**: Live code editing
- **FPM Configuration**: Optimized for development
- **Error Display**: PHP errors shown in development mode

## 📁 Recommended Project Organization

Create a dedicated folder inside public_html that will contain a symbolic link for each project.
Each symbolic link should point to the project’s public folder (where index.php is located).

```
~/sites/
├── laravel-app   → symbolic link to Laravel’s /public folder
├── symfony-app   → symbolic link to Symfony’s /public folder
└── plain-php     → symbolic link to the folder containing 
```

This setup keeps your project URLs clean. For example:

Laravel app → `laravel-app--site.phpforge.dev`

Symfony app → `symfony-app--site.phpforge.dev`

Plain PHP app → `plain-php--site.phpforge.dev`

### Example: Creating a symbolic link
#### Example for a Laravel project
`ln -s /public_html/projects/laravel-app/public ~/sites/laravel-app`

#### Example for a Symfony project
`ln -s /public_html/projects/symfony-app/public ~/sites/symfony-app`

#### Example for a plain PHP project
`ln -s /public_html/projects/plain-php ~/sites/plain-php`

## 🐛 Troubleshooting

### ❓ Common Issues

- **DNS resolution not working**: Ensure you ran `./setup-local-dns.sh` and restarted your browser or system. You may need to flush DNS cache.
- **SSL certificate not trusted**: Make sure you ran `./install_cert.sh` and restart your browser afterwards. Check the CA is present with `openssl verify -CAfile .caroot/rootCA.pem certificates/php-devforge.pem`. Firefox keeps its own trust store on Linux, so install `nss` (Arch) or `libnss3-tools` (Debian/Ubuntu) and re-run the script if Firefox still complains.
- **Containers not starting**: Check that Docker and Docker Compose are installed and running. Ensure ports 80 and 443 are not in use by other services.
- **Permission issues with public_html**: Check that `PUID`/`PGID` in `.env` match your own ids (`id -u`, `id -g`), then recreate the containers with `docker compose up -d --force-recreate`. The containers adopt those ids on startup, so files they write are owned by you.
- **PHP version not switching**: Use the aliases `forge:use:php83` or `forge:use:php84` to change the default version, or append `--p83`/`--p84` to the URL.
- **Aliases not working**: Ensure you sourced `aliases.bash` or added it to your `~/.bashrc`.

For more help, check the logs with `docker-compose logs` or create an issue on GitHub.

## 🤝 Contributing

We welcome contributions to improve PHP DevForge! Please follow these guidelines:

### ⚙️ Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly with different PHP versions and configurations
5. Update documentation if needed

### 📏 Code Standards
- Follow Docker best practices
- Use clear, descriptive commit messages
- Test configurations on multiple platforms (Linux, macOS)
- Ensure backward compatibility

### 🧪 Testing
- Test SSL certificate generation
- Verify DNS resolution works
- Check PHP version switching
- Validate volume mounting and live editing
- Test with different project structures

### 📚 Documentation
- Update README for new features
- Document configuration options
- Provide examples for common use cases
- Keep installation instructions current

### 📤 Submitting Changes
1. Ensure all tests pass
2. Update CHANGELOG.md if applicable
3. Submit a pull request with detailed description
4. Address review feedback promptly

### 🐛 Reporting Issues
- Use GitHub issues for bug reports
- Include your OS, Docker version, and PHP version
- Provide steps to reproduce
- Attach relevant logs and configuration files

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 💬 Support

For questions or issues:
- Check the troubleshooting section in documentation
- Search existing GitHub issues
- Create a new issue with detailed information

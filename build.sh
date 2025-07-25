#!/bin/bash
set -e

# Configuration
MOD_NAME="FS25_NotificationLog"
BUILD_DIR="build"

MODS_DIR_WINDOWS="$HOME/Documents/My Games/FarmingSimulator2025/mods"
MODS_DIR_MAC="$HOME/Library/Application Support/FarmingSimulator2025/mods"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

########
# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Safer delete of directory and its contents
delete_dir() {
    local dir_path="$1"
    
    if [[ -z "$dir_path" ]]; then
        log_error "delete_dir: No directory path provided"
        return 1
    fi
    
    if [[ ! -d "$dir_path" ]]; then
        return 0
    fi
    
    # Only delete regular files and empty directories
    find "$dir_path" -depth \( -type f -o -type d -empty \) -delete
}

# Some safety checks to validate and resolve build directory
validate_build_dir() {
    local build_dir="$1"
    
    # Check if realpath is available
    if ! command -v realpath &> /dev/null; then
        log_error "realpath command not found. Required for safer directory operations."
        exit 1
    fi
    
    # Get absolute paths
    local script_dir
    script_dir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
    local target_dir="$script_dir/$build_dir"
    
    # Validate build directory name doesn't contain traversal attempts
    if [[ "$build_dir" =~ \.\./|\.\.\\ ]]; then
        log_error "Build directory contains directory traversal: '$build_dir'"
        exit 1
    fi
    
    # Ensure target directory is within script directory
    if [[ ! "$target_dir" == "$script_dir"/* ]]; then
        log_error "Build directory must be a subdirectory of script location"
        log_error "Script dir: $script_dir"
        log_error "Target dir: $target_dir"
        exit 1
    fi
    
    echo "$target_dir"
}


######## 
# Build functions

# Validate mod structure and files
validate_mod() {
    log_info "Validating mod structure..."
    
    # Check required files
    if [[ ! -f "modDesc.xml" ]]; then
        log_error "modDesc.xml is missing"
        exit 1
    fi
    
    # Check for any icon file (icon_*.dds pattern)
    local icon_files=(icon_*.dds)
    if [[ ! -f "${icon_files[0]}" ]]; then
        log_warning "No icon file (icon_*.dds) found in root directory"
    fi
    
    if [[ ! -d "scripts" ]]; then
        log_error "scripts/ directory is missing"
        exit 1
    fi
    
    # Check that scripts referenced in modDesc.xml exist
    if command -v xmllint &> /dev/null; then
        log_info "Validating referenced script files..."
        
        # Extract sourceFile filenames from modDesc.xml
        local source_files
        source_files=$(xmllint --xpath "//sourceFile/@filename" modDesc.xml 2>/dev/null | grep -o 'filename="[^"]*"' | sed 's/filename="//;s/"//' || true)
        
        if [[ -n "$source_files" ]]; then
            while IFS= read -r script_file; do
                if [[ ! -f "$script_file" ]]; then
                    log_error "Referenced script file '$script_file' is missing"
                    exit 1
                fi
            done <<< "$source_files"
            log_success "All referenced script files exist"
        else
            log_warning "No sourceFile entries found in modDesc.xml"
        fi
    else
        log_warning "xmllint not available, skipping script file validation"
    fi
    
    # Validate XML syntax (if xmllint is available)
    if command -v xmllint &> /dev/null; then
        log_info "Validating XML files..."
        
        # Validate all XML files recursively, excluding those in .gitignore
        while IFS= read -r -d '' xml_file; do
            if ! git check-ignore "$xml_file" &>/dev/null; then
                if ! xmllint --noout "$xml_file" 2>/dev/null; then
                    log_error "$xml_file has invalid XML syntax"
                    exit 1
                fi
            fi
        done < <(find . -name "*.xml" -type f -print0)
        
        log_success "All XML files are valid"
    else
        log_warning "xmllint not found, skipping XML validation"
    fi
    
    # Check for Lua syntax errors (if luac is available)
    if command -v luac &> /dev/null; then
        log_info "Validating Lua syntax..."
        
        # Find all .lua files recursively, excluding those in .gitignore
        while IFS= read -r -d '' lua_file; do
            if ! git check-ignore "$lua_file" &>/dev/null; then
                if ! luac -p "$lua_file" &>/dev/null; then
                    log_error "$lua_file has Lua syntax errors"
                    exit 1
                fi
            fi
        done < <(find . -name "*.lua" -type f -print0)
        
        log_success "All Lua files have valid syntax"
    else
        log_warning "luac not found, skipping Lua syntax validation"
    fi
    
    # Check version consistency with latest git tag
    if command -v git &> /dev/null && git rev-parse --git-dir &>/dev/null; then
        log_info "Validating version consistency..."
        
        local mod_version=$(get_version)
        local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
        
        if [[ -n "$latest_tag" ]]; then
            # Remove 'v' prefix from tag if present
            local tag_version=${latest_tag#v}
            
            if [[ "$mod_version" != "$tag_version" ]]; then
                log_warning "Version mismatch: modDesc.xml has '$mod_version' but latest git tag is '$latest_tag'"
                log_warning "Please update modDesc.xml version or create a new git tag"
                exit 1
            else
                log_success "Version '$mod_version' matches git tag '$latest_tag'"
            fi
        else
            log_warning "No git tags found, skipping version validation"
        fi
    else
        log_warning "Git not available, skipping version validation"
    fi
    
    log_success "Mod structure validation completed"
}

# Extract version from modDesc.xml
get_version() {
    if command -v xmllint &> /dev/null; then
        xmllint --xpath "string(//version)" modDesc.xml 2>/dev/null || echo "unknown"
    else
        grep -o '<version>[^<]*</version>' modDesc.xml | sed 's/<[^>]*>//g' || echo "unknown"
    fi
}

# Create release package
package_mod() {
    local version=$(get_version)
    log_info "Creating release package for version $version..."
    
    # Clean and create build directory safely
    local build_path
    build_path=$(validate_build_dir "$BUILD_DIR")
    
    if [[ -d "$build_path" ]]; then
        log_info "Removing existing build directory: $build_path"
        delete_dir "$build_path"
    fi
    
    mkdir -p "$build_path"
    BUILD_DIR="$build_path"
    
    # Copy mod files, excluding what's in .gitignore and build files
    log_info "Copying mod files..."
    
    # Create exclude file from .gitignore plus additional build exclusions
    local exclude_file=$(mktemp)
    {
        # Add .gitignore contents if it exists
        [[ -f .gitignore ]] && cat .gitignore
        # Add additional build-specific exclusions
        echo ".git*"
        echo "*.md"
        echo "build.sh"
        echo "package.json"
        echo "node_modules/"
        echo ".*rc*"
        echo ".editorconfig"
        echo ".prettier*"
    } > "$exclude_file"
    
    rsync -av \
        --exclude-from="$exclude_file" \
        . "$BUILD_DIR/$MOD_NAME/"
    
    # Cleanup temp file
    rm "$exclude_file"
    
    # Create versioned zip file
    local zip_name="${MOD_NAME}.zip"
    log_info "Creating zip package: $zip_name"
    
    # Save current directory and change to build directory
    local original_dir=$(pwd)
    cd "$BUILD_DIR"
    
    if command -v zip &> /dev/null; then
        zip -r "$zip_name" "$MOD_NAME/" > /dev/null
    else
        log_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    # Return to original directory
    cd "$original_dir"
    
    log_success "Package created: $BUILD_DIR/$zip_name"
}

# Deploy to local mods folder
deploy_local() {
    log_info "Deploying to local mods folder..."
    
    # Determine mods directory based on OS
    local mods_dir=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mods_dir="$MODS_DIR_MAC"
    else
        mods_dir="$MODS_DIR_WINDOWS"
    fi
    
    if [[ ! -d "$mods_dir" ]]; then
        log_warning "Mods directory not found: $mods_dir"
        log_info "You can manually copy the zip file from $BUILD_DIR to your FS25 mods folder"
        return
    fi
    
    # Use the same zip filename as created in package_mod
    local zip_name="${MOD_NAME}.zip"
    local zip_file="$BUILD_DIR/$zip_name"
    
    if [[ ! -f "$zip_file" ]]; then
        log_error "Zip file not found: $zip_file"
        log_error "Run 'package' first to create the zip file"
        exit 1
    fi
    
    # Copy zip file to mods directory (overwriting if exists)
    log_info "Copying $zip_name to mods directory"
    cp "$zip_file" "$mods_dir/"
    
    log_success "Mod zip deployed to: $mods_dir/$zip_name"
}

# Clean build artifacts
clean() {
    log_info "Cleaning build artifacts..."
    
    local build_path
    build_path=$(validate_build_dir "$BUILD_DIR")
    
    if [[ -d "$build_path" ]]; then
        log_info "Removing build directory: $build_path"
        delete_dir "$build_path"
        log_success "Build directory cleaned"
    else
        log_info "Build directory does not exist"
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build     - Validate and package the mod (default)"
    echo "  validate  - Only validate mod structure and syntax"
    echo "  package   - Only create the package"
    echo "  deploy    - Deploy to local mods folder"
    echo "  clean     - Clean build artifacts"
    echo "  help      - Show this help message"
    echo ""
    echo "Full build process: validate -> package -> deploy"
}

# Main execution
main() {
    local command=${1:-build}
    
    case "$command" in
        "build")
            validate_mod
            package_mod
            log_success "Build completed successfully!"
            ;;
        "validate")
            validate_mod
            ;;
        "package")
            validate_mod
            package_mod
            ;;
        "deploy")
            if [[ ! -d "$BUILD_DIR/$MOD_NAME" ]]; then
                log_error "No built mod found. Run 'package' first."
                exit 1
            fi
            deploy_local
            ;;
        "clean")
            clean
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
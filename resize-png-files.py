#!/usr/bin/env python3
"""
PNG Image Resizer

This script resizes PNG images in a specified folder by a given percentage.
Supports recursive processing of subdirectories.

Requirements:
    pip install Pillow

Usage:
    python resize-png-files.py --folder ./images --percentage 50
    python resize-png-files.py -f ./images -p 75 --recursive
"""

import argparse
import os
import sys
from pathlib import Path
from PIL import Image


def resize_image(image_path, output_path, percentage):
    """
    Resize a single PNG image by the specified percentage.
    
    Args:
        image_path: Path to the input image
        output_path: Path to save the resized image
        percentage: Resize percentage (e.g., 50 for 50% of original size)
    """
    try:
        with Image.open(image_path) as img:
            # Calculate new dimensions
            width, height = img.size
            new_width = int(width * (percentage / 100))
            new_height = int(height * (percentage / 100))
            
            # Resize image using high-quality resampling
            resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            # Save the resized image
            resized_img.save(output_path, 'PNG', optimize=True)
            
            print(f"✓ Resized: {image_path.name} ({width}x{height} → {new_width}x{new_height})")
            return True
    except Exception as e:
        print(f"✗ Error processing {image_path.name}: {e}", file=sys.stderr)
        return False


def process_folder(folder_path, percentage, recursive=False, output_folder=None, overwrite=False):
    """
    Process all PNG files in the specified folder.
    
    Args:
        folder_path: Path to the folder containing PNG files
        percentage: Resize percentage
        recursive: Process subdirectories recursively
        output_folder: Optional output folder (default: overwrite originals or create 'resized' folder)
        overwrite: If True, overwrite original files; if False, save to output folder
    """
    folder = Path(folder_path)
    
    if not folder.exists():
        print(f"Error: Folder '{folder_path}' does not exist.", file=sys.stderr)
        return False
    
    if not folder.is_dir():
        print(f"Error: '{folder_path}' is not a directory.", file=sys.stderr)
        return False
    
    # Determine output folder
    if output_folder:
        out_path = Path(output_folder)
        out_path.mkdir(parents=True, exist_ok=True)
    elif not overwrite:
        out_path = folder / 'resized'
        out_path.mkdir(exist_ok=True)
    else:
        out_path = None  # Will overwrite in place
    
    # Find PNG files
    pattern = '**/*.png' if recursive else '*.png'
    png_files = list(folder.glob(pattern))
    
    if not png_files:
        print(f"No PNG files found in '{folder_path}'")
        return True
    
    print(f"Found {len(png_files)} PNG file(s) to process")
    print(f"Resize percentage: {percentage}%")
    print(f"{'Overwriting originals' if overwrite or not out_path else f'Output folder: {out_path}'}")
    print("-" * 60)
    
    success_count = 0
    failed_count = 0
    
    for png_file in png_files:
        # Determine output path
        if out_path:
            if recursive:
                # Preserve directory structure
                rel_path = png_file.relative_to(folder)
                output_file = out_path / rel_path
                output_file.parent.mkdir(parents=True, exist_ok=True)
            else:
                output_file = out_path / png_file.name
        else:
            output_file = png_file
        
        if resize_image(png_file, output_file, percentage):
            success_count += 1
        else:
            failed_count += 1
    
    print("-" * 60)
    print(f"Complete: {success_count} succeeded, {failed_count} failed")
    
    return failed_count == 0


def main():
    parser = argparse.ArgumentParser(
        description='Resize PNG images by a specified percentage',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --folder ./images --percentage 50
  %(prog)s -f ./images -p 75 --recursive
  %(prog)s -f ./images -p 25 --output ./thumbnails
  %(prog)s -f ./images -p 50 --overwrite
        """
    )
    
    parser.add_argument(
        '-f', '--folder',
        required=True,
        help='Folder containing PNG files to resize'
    )
    
    parser.add_argument(
        '-p', '--percentage',
        type=float,
        required=True,
        help='Resize percentage (e.g., 50 for 50%% of original size)'
    )
    
    parser.add_argument(
        '-r', '--recursive',
        action='store_true',
        help='Process subdirectories recursively'
    )
    
    parser.add_argument(
        '-o', '--output',
        help='Output folder (default: creates "resized" subfolder or overwrites if --overwrite is set)'
    )
    
    parser.add_argument(
        '--overwrite',
        action='store_true',
        help='Overwrite original files (use with caution)'
    )
    
    args = parser.parse_args()
    
    # Validate percentage
    if args.percentage <= 0:
        print("Error: Percentage must be greater than 0", file=sys.stderr)
        sys.exit(1)
    
    if args.percentage > 500:
        print("Warning: Percentage > 500% may produce very large files")
    
    # Process files
    success = process_folder(
        args.folder,
        args.percentage,
        recursive=args.recursive,
        output_folder=args.output,
        overwrite=args.overwrite
    )
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

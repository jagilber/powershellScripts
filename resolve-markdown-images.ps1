<#
.SYNOPSIS
script to search git repo and validate image paths in .md

.DESCRIPTION
script to search git repo for images in .md and their location
optionally update broken links with -repair

.LINK
    [net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
    iwr https://raw.githubusercontent.com/jagilber/powershellScripts/master/resolve-markdown-images.ps1 -outFile $pwd\resolve-markdown-images.ps1

.EXAMPLE
    .\resolve-markdown-images.ps1 -markdownFolder $pwd -mediaFolder $pwd/../.attachments -whatIf -repoRootPath $pwd/..
#>
[cmdletbinding()]
param(
    $markdownFolder = $pwd,
    $mediaFolder = $markdownFolder,
    $repoRootPath = '',
    # [switch]$useRelativePaths,
    [switch]$repair, # = $true,
    [switch]$whatIf, #= $true
    [switch]$checkImagesWithoutArticles
)

$global:images = $null
$global:articles = $null

$global:imagesWithoutArticlesList = [collections.arraylist]::new()
$global:badImagePathTable = @{} 
$global:articlesImagesPathTable = @{}
$regexOptions = [text.regularexpressions.regexoptions]::ignorecase -bor [text.regularexpressions.regexoptions]::multiline

function main() {
    if (!(test-path $mediaFolder)) {
        write-error "$mediaFolder does not exist"
        return
    }

    if (!(test-path $markdownFolder)) {
        write-error "$markdownFolder does not exist"
        return
    }

    $global:images = Get-ChildItem -Recurse -File -Path $mediaFolder | Where-Object Name -imatch "\.gif|\.jpg|\.png"
    write-host "images:`r`n$($global:images | out-string)"

    $global:articles = Get-ChildItem -Recurse -File -Filter '*.md' -Path $markdownFolder
    write-host "articles:`r`n$($global:articles | out-string)"    
    $global:articlesImagesPathTable = get-imagePathsFromArticle -articles $global:articles -images $global:images

    if ($checkImagesWithoutArticles) {
        $global:imagesWithoutArticlesList = get-imagesWithNoArticles -images $images -imagePathTable $global:articlesImagesPathTable
    }
    
    $global:badImagePathTable = get-articleBadImages -imagePathTable $global:articlesImagesPathTable

    write-verbose "`$global:articlesImagesPathTable:`r`n$($global:articlesImagesPathTable | convertto-json)"
    write-host "`$global:imagesWithoutArticlesList:`r`n$($global:imagesWithoutArticlesList | out-string)" -ForegroundColor yellow
    write-host "`$global:badImagePathTable:`r`n$($global:badImagePathTable | convertto-json)" -ForegroundColor yellow

    write-host "finished. check:
        `$global:badImagePathTable
        `$global:imagesWithoutArticlesList
        `$global:articlesImagesPathTable" -ForegroundColor Cyan
}

function get-imagePathsFromArticle($articles, $images) {
    $table = @{}

    foreach ($article in $articles) {
        Write-host ">checking article for images:$($article.FullName)" -foregroundcolor green
        $articleContent = Get-Content -Raw -Path $article.FullName
        #$imageLinkPattern = "([^\[\]!\(\)\`" :=']+\.png|.jpg|.gif)"
        #$imageLinkPattern = "([^\[\]!\(\)\`" :=']+(?:\.png|\.jpg|\.gif))"
        $imageLinkPattern = "\[.*?\].+?([^!\(\)\`" :=']+(?:\.png|\.jpg|\.gif))"

        if ([regex]::IsMatch($articleContent, $imageLinkPattern, $regexOptions)) {
            $imageMatches = [regex]::Matches($articleContent, $imageLinkPattern, $regexOptions)
            
            foreach ($match in $imageMatches) {
                $error.clear()
                $imagePath = $match.Groups[1].Value.trim()
                $articlePath = [io.path]::GetDirectoryName($article.FullName)
                if ($imagePath.StartsWith('/')) {
                    $imageRootPath = $repoRootPath
                }
                else {
                    $imageRootPath = $articlePath
                }
                write-host "checking path `"$($imageRootPath)/$($imagePath)`" `"$repoRootPath`"" -ForegroundColor Darkgreen
                $imagePathInfo = get-path "$($imageRootPath)/$($imagePath)" "$repoRootPath"
                $imageFullPath = $imagePathInfo.fullFilePath
                #$imageFullPath = resolve-path ("$([io.path]::GetDirectoryName($article.FullName))\$imagePath".replace('\', '/')) -ErrorAction SilentlyContinue
                write-host "`tchecking path:$imageFullPath" -ForegroundColor darkgreen
                $imageFound = $true
                if ($error) {
                    
                    $error.Clear()
                }
                if (!$table.Count -or !($table.containsKey($article.FullName))) {
                    [void]$table.Add($article.FullName, [collections.ArrayList]::new())
                }

                #if (!$imageFullPath -or !(test-path $imageFullPath)) {
                if (!$imageFullPath -or !($imagePathInfo.pathType -eq 'File')) {
                    Write-Warning "bad path: $imagePath"
                    Write-Warning "adding bad image path:`r`n`t$($imagePath)`r`n`tfor article:`r`n`tfile://$($article.FullName.replace('\', '/'))"

                    $imageFound = $false
                    if ($repair) {
                        $newPath = repair-articleImagePath -article $article -imagePath $imagePath -images $images
                    }
                }
                else {
                    write-host "`timage found: $imageFullPath" -ForegroundColor Green
                }
                [void]$table[$article.FullName].Add(@{
                        pathInMd = $imagePath
                        fullPath = $imageFullPath
                        found    = $imageFound
                        newPath  = $newPath
                    }
                )
            }
        }
    }

    return $table
}

function get-path($path, $repoRootPath = '') {
    # only pass in a path, not a file
    # return a full path, a relative path, a path from the repo root, and a path with repo root as root path in a new object
    write-verbose "get-path '$path' '$repoRootPath'"
    $pathType = "Unknown"
    $tempPath = $path
    if (Test-Path $path -PathType Leaf) {
        $pathType = "File"
        $tempPath = [io.path]::GetDirectoryName($path)
    }
    elseif (Test-Path $path -PathType Container) {
        $pathType = "Directory"
    }
    elseif (!(Test-Path $path)) {
        $pathType = "Not Found"
    }
    
    $fullFilePath = (resolve-path $path -ErrorAction SilentlyContinue)
    if ($fullFilePath) { $fullFilePath = $fullFilePath.Path.Replace('\', '/') }
    $fullPath = (resolve-path $tempPath -ErrorAction SilentlyContinue)
    if ($fullPath) {
        $fullPath = $fullPath.Path.Replace('\', '/') 
        $relativePath = [io.path]::GetRelativePath($pwd, $fullPath).Replace('\', '/')
    }

    if ($repoRootPath) {
        $repoRootFullPath = (resolve-path $repoRootPath).Path.Replace('\', '/')
        write-verbose "repoRootFullPath: $repoRootFullPath"
        if ($fullPath) {
            $repoPath = '/' + [io.path]::GetRelativePath($repoRootFullPath, $fullPath).Replace('\', '/')
        }
        $relativeRepoPath = [io.path]::GetRelativePath($pwd, $repoRootFullPath).Replace('\', '/')
    }
    $result = [ordered]@{
        path             = $path
        pathType         = $pathType
        fullPath         = $fullPath
        fullFilePath     = $fullFilePath
        relativePath     = $relativePath
        repoPath         = $repoPath
        relativeRepoPath = $relativeRepoPath
    }
    write-host "get-path '$path' returning: $($result | convertto-json)" -ForegroundColor Cyan
    return $result
}

function get-articleBadImages($imagePathTable) {
    write-host "checking for bad images in articles" -ForegroundColor Cyan
    $table = @{}

    foreach ($article in $imagePathTable.GetEnumerator()) {
        foreach ($image in $article.Value.GetEnumerator()) {
            write-verbose "checking $($article.Name) image $($image.pathinMd)"
            if (!($image.found)) {
                write-warning "missing image in $($article) image $($image.pathinMd)"
                if (!$table.Count -or !($table.containsKey($article.Name))) {
                    [void]$table.Add($article.Name, [collections.ArrayList]::new())
                }
                
                [void]$table[$article.Name].Add(@{
                        mdFile   = "file://$($article.Name.replace('\', '/'))"
                        pathinMd = $image.pathinMd
                        newPath  = $image.newPath
                    }
                )
            }
        }
    }
    return $table
}

function get-imagesWithNoArticles($images, $imagePathTable) {
    write-host "checking images with no articles" -ForegroundColor Cyan
    $list = [collections.arraylist]::new()
    foreach ($image in $images) {
        $found = $false
        foreach ($article in $imagePathTable.GetEnumerator()) {
            write-verbose "checking $($article.Name) image $($image.FullName)"
            if ($article.value.fullpath -ilike $image.FullName ) {
                $found = $true
                break    
            }
        }
        if (!$found) {
            [void]$list.Add($image.FullName)
        }
    }
    return $list
}

function repair-articleImagePath($article, $imagePath, $images) {
    write-host "repair-articleImagePath $article $imagePath $images" -ForegroundColor Cyan
    $articlePath = [io.path]::GetDirectoryName($article.FullName)
    $newContent = Get-Content -Raw -Path $article.FullName
    $imagePathFileName = [io.path]::GetFileName($imagePath)
    write-host "checking images list for file name:$imagePathFileName"
    $relativePath = ''
    $imageFiles = @($images | Where-Object Name -ieq $imagePathFileName)

    if ($imageFiles.Count -eq 1) {
        $relativePath = [io.path]::GetRelativePath($articlePath, $imageFiles[0].FullName).replace('\', '/')
    }
    else {
        write-error "unable to fix $imagePath`r`nmatching images:$imageFiles"
        return $relativePath
    }

    write-host "updating article $($article.Name) with new image path $($relativePath)" -ForegroundColor Magenta

    if (!$whatIf) {
        $newContent = $newContent.Replace($imagePath, $relativePath)
        write-verbose "new content:`r`n$newContent"
        out-file -InputObject $newContent -FilePath $article.FullName -NoNewline
    }
    
    return $relativePath
}

main


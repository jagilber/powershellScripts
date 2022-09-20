<#
search git repo for images in .md and their location
optionally update broken links with -repair
#>
[cmdletbinding()]
param(
    $markdownFolder = $pwd,
    $mediaFolder = $markdownFolder,
    [switch]$repair, # = $true,
    [switch]$whatIf #= $true
)

$global:images = $null
$global:articles = $null

$global:imagesWithoutArticlesList = [collections.arraylist]::new()
$global:badImagePathTable = @{} 
$global:articlesImagesPathTable = @{}

function main() {
    if (!(test-path $mediaFolder)) {
        write-error "$mediaFolder does not exist"
        return
    }

    if (!(test-path $markdownFolder)) {
        write-error "$markdownFolder does not exist"
        return
    }

    $global:images = Get-ChildItem -Recurse -File -Filter '*.png' -Path $mediaFolder
    write-host "images:`r`n$($global:images | out-string)"

    $global:articles = Get-ChildItem -Recurse -File -Filter '*.md' -Path $markdownFolder
    write-host "articles:`r`n$($global:articles | out-string)"    
    $global:articlesImagesPathTable = get-imagePathsFromArticle -articles $global:articles -images $global:images

    $global:imagesWithoutArticlesList = get-imagesWithNoArticles -images $images -imagePathTable $global:articlesImagesPathTable
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
        Write-host "checking article for images:$($article.FullName)" -foregroundcolor green
        $articleContent = Get-Content -Raw -Path $article.FullName
        #$imageLinkPattern = "([^\[\]!\(\)\`" :=']+\.png|.jpg|.gif)"
        #$imageLinkPattern = "([^\[\]!\(\)\`" :=']+(?:\.png|\.jpg|\.gif))"
        $imageLinkPattern = "\[.*?\].+?([^!\(\)\`" :=']+(?:\.png|\.jpg|\.gif))"

        if ([regex]::IsMatch($articleContent, $imageLinkPattern,[text.regularexpressions.regexoptions]::ignorecase -bor [text.regularexpressions.regexoptions]::multiline)) {
            $matches = [regex]::Matches($articleContent, $imageLinkPattern,[text.regularexpressions.regexoptions]::ignorecase -bor [text.regularexpressions.regexoptions]::multiline)
            
            foreach ($match in $matches) {
                $error.clear()
                $imagePath = $match.Groups[1].Value.trim()
                write-verbose "resolve-path (`"`$([io.path]::GetDirectoryName($($article.FullName)))\$imagePath`".replace('\', '/'))"
                $imageFullPath = resolve-path ("$([io.path]::GetDirectoryName($article.FullName))\$imagePath".replace('\', '/')) #-ErrorAction SilentlyContinue
                write-host "`tchecking path:$imageFullPath" -ForegroundColor darkgreen
                $imageFound = $true
                if($error){
                    
                    $error.Clear()
                }
                if (!$table.Count -or !($table.containsKey($article.FullName))) {
                    [void]$table.Add($article.FullName, [collections.ArrayList]::new())
                }

                if (!$imageFullPath -or !(test-path $imageFullPath)) {
                    Write-Warning "bad path: $imageFullPath"
                    Write-Warning "adding bad image path:`r`n`t$($imageFullPath)`r`n`tfor article:`r`n`t$($article.FullName)"

                    $imageFound = $false
                    if ($repair) {
                        $articleContent = repair-articleImagePath -article $article -imagePath $imagePath -images $images
                    }
                }

                [void]$table[$article.FullName].Add(@{
                        path     = $imagePath
                        fullPath = $imageFullPath
                        found    = $imageFound
                    }
                )
            }
        }
    }

    return $table
}

function get-articleBadImages($imagePathTable) {
    $table = @{}

    foreach ($article in $imagePathTable.GetEnumerator()) {
        foreach ($image in $article.Value.GetEnumerator()) {
            write-verbose "checking $($article.Name) image $($image.path)"
            if (!($image.found)) {
                write-warning "missing image in $($article) image $($image.path)"
                if (!$table.Count -or !($table.containsKey($article.Name))) {
                    [void]$table.Add($article.Name, [collections.ArrayList]::new())
                }
                [void]$table[$article.Name].Add($image.path)
            }
        }
    }
    return $table
}

function get-imagesWithNoArticles($images, $imagePathTable) {
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
    $articlePath = [io.path]::GetDirectoryName($article.FullName)
    $newContent = Get-Content -Raw -Path $article.FullName
    $imagePathFileName = [io.path]::GetFileName($imagePath)
    write-host "checking images list for file name:$imagePathFileName"
    
    if ($images.Name -contains $imagePathFileName) {
        $imageFile = $images | Where-Object Name -ieq $imagePathFileName
        $relativePath = [io.path]::GetRelativePath($articlePath, $imageFile.FullName).replace('\', '/')
    }
    else {
        write-warning "unable to fix $imagePath"
    }

    write-host "updating article $($article.Name) with new image path $($relativePath)" -ForegroundColor Magenta
    if (!$whatIf) {
        $newContent = $newContent.Replace($imagePath, $relativePath)
        write-verbose "new content:`r`n$newContent"
        out-file -InputObject $newContent -FilePath $article.FullName -NoNewline
    }
    
    return $newContent
}

main


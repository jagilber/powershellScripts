<#
search git repo for images in .md and their location
#>
[cmdletbinding()]
param(
    $mediaFolder,
    $markdownFolder
)

$images = $null
$articles = $null

$global:imagesWithArticlesTable = @{}
$global:articlesWithImagesTable = @{}
$global:imagesWithoutArticlesList = [collections.arraylist]::new()
$global:articlesWithoutImagesList = [collections.arraylist]::new()
$global:badImagePathTable = @{} # [collections.arraylist]::new()
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

    #$images = [io.directory]::GetFiles($mediaFolder,'*.png',[IO.SearchOption]::AllDirectories)
    $images = Get-ChildItem -Recurse -File -Filter '*.png' -Path $mediaFolder
    write-host "images:`r`n$($images | out-string)"

    #$articles = [io.directory]::GetFiles($markdownFolder,'*.md',[IO.SearchOption]::AllDirectories)
    $articles = Get-ChildItem -Recurse -File -Filter '*.md' -Path $markdownFolder
    write-host "articles:`r`n$($articles | out-string)"

    $global:articlesWithImagesTable = find-articlesWithImage -images $images -articles $articles

    $global:imagesWithArticlesTable = find-imagesForArticle -images $images -articles $articles

    foreach ($article in $articles) {
        if (!($global:articlesWithImagesTable.containsKey($article.FullName))) {
            Write-Verbose "no images in article:$($article.FullName)"
            [void]$global:articlesWithoutImagesList.Add($article.FullName)
        }
    }

    foreach ($image in $images) {
        if (!($global:imagesWithArticlesTable.containsKey($image.FullName))) {
            write-host "no articles for image:$($image.FullName)" -ForegroundColor Yellow
            [void]$global:imagesWithoutArticlesList.Add($image.FullName)
        }
    }
    
    $global:articlesImagesPathTable = get-imagePathsFromArticle($articles)

    write-host "`$global:articlesWithImagesTable:`r`n$($global:articlesWithImagesTable | out-string)"
    write-host "`$global:imagesWithArticlesTable:`r`n$($global:imagesWithArticlesTable | out-string)"
    write-host "`$global:articlesImagesPathTable:`r`n$($global:articlesImagesPathTable | out-string)"
    write-host "`$global:imagesWithoutArticlesList:`r`n$($global:imagesWithoutArticlesList | out-string)" -ForegroundColor yellow
    write-host "`$global:badImagePathTable:`r`n$($global:badImagePathTable | out-string)" -ForegroundColor yellow
    Write-Verbose "`$global:articlesWithoutImagesList:`r`n$($global:articlesWithoutImagesList | out-string)"

    write-host "finished. check:
        `$global:articlesWithImagesTable
        `$global:imagesWithArticlesTable
        `$global:articlesWithoutImagesList
        `$global:imagesWithoutArticlesList
        `$global:badImagePathTable
        `$global:articlesImagesPathTable" -ForegroundColor Cyan
}

function find-articlesWithImage($images, $articles) {
    $table = @{}
    foreach ($image in $images) {
        foreach ($article in $articles) {
            Write-verbose "checking article:`r`n`t$($article.FullName)`r`n`tfor image:`r`n`t$($image.FullName)"
            $articleContent = Get-Content -Path $article.FullName

            if ([regex]::IsMatch($articleContent, $image.Name, [text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            
                if (!$table.Count -or !($table.containsKey($article.FullName))) {
                    [void]$table.Add($article.FullName, [collections.arraylist]::new())
                }

                Write-host "adding article:`r`n`t$($article.FullName)`r`n`tfor image:`r`n`t$($image.FullName)" -ForegroundColor Green
                [void]$table[$article.FullName].Add($image.FullName)
            }
        }
    }

    return $table
}

function find-imagesForArticle($images, $articles) {
    $table = @{}
    foreach ($image in $images) {
        foreach ($article in $articles) {
            Write-verbose "checking article:`r`n`t$($article.FullName)`r`n`tfor image:`r`n`t$($image.FullName)"
            $articleContent = Get-Content -Raw -Path $article.FullName
        
            if ([regex]::IsMatch($articleContent, $image.Name, [text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    
                if (!$table.Count -or !($table.containsKey($image.FullName))) {
                    [void]$table.Add($image.FullName, [collections.arraylist]::new())
                }
        
                Write-host "adding image:`r`n`t$($image.FullName)`r`n`tfor article:`r`n`t$($article.FullName)" -ForegroundColor Green
                [void]$table[$image.FullName].Add($article.FullName)

                write-host "checking path for $($image.Name)"
                $matches = [regex]::Matches($articleContent, "\((.+?$($image.Name))\)", [text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($match in $matches) {
                    $imagePath = "$([io.path]::GetDirectoryName($article.FullName))\$($match.Groups[1].Value)".replace('\', '/')
                    write-host "checking path:$imagePath" -ForegroundColor Green
                    if (!(test-path $imagePath)) {
                        Write-Warning "bad path: $imagePath"
                        if (!$global:badImagePathTable.Count -or !($global:badImagePathTable.containsKey($article.FullName))) {
                            [void]$global:badImagePathTable.Add($article.FullName, [collections.arraylist]::new())
                        }
                
                        Write-Warning "adding bad image path:`r`n`t$($image.FullName)`r`n`tfor article:`r`n`t$($article.FullName)"
                        [void]$global:badImagePathTable[$article.FullName].Add($images.FullName)
        
                    }
                }
            }
        }
    }

    return $table
}

function get-imagePathsFromArticle($articles) {
    $table = @{}

    foreach ($article in $articles) {
        Write-verbose "checking article for images:`r`n`t$($article.FullName)"
        $articleContent = Get-Content -Raw -Path $article.FullName
        $imageLinkPattern = '!\[.+?\]\((.+?)\)'

        if ([regex]::IsMatch($articleContent, $imageLinkPattern)) {
            $matches = [regex]::Matches($articleContent, $imageLinkPattern)
            
            foreach ($match in $matches) {
                $imagePath = $match.Groups[1].Value
                $imageFullPath = "$([io.path]::GetDirectoryName($article.FullName))\$imagePath".replace('\', '/')
                write-host "checking path:$imageFullPath" -ForegroundColor Green
                $imageFound = $true
                
                if (!$table.Count -or !($table.containsKey($article.FullName))) {
                    [void]$table.Add($article.FullName, [collections.ArrayList]::new())
                }

                if (!(test-path $imageFullPath)) {
                    Write-Warning "bad path: $imageFullPath"
                    Write-Warning "adding bad image path:`r`n`t$($imageFullPath)`r`n`tfor article:`r`n`t$($article.FullName)"
                    $imageFound = $false
                }

                [void]$table[$article.FullName].Add(@{
                        path = $imagePath
                        fullPath  = $imageFullPath
                        found = $imageFound
                    }
                )
            }
        }
    }

    return $table
}

main


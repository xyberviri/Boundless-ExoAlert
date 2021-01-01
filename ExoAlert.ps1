<#
    Title: Exo Alert 
    Version: 0.5.0
    Author: James Velasquez. aka Xyberviri, Emareks
    Description: This script checks for new exo planets
    Requirements Powershell 7+, gdi+ on linux ( `sudo apt-get install libgdiplus` )
    
    This work is licensed under the GNU GENERAL PUBLIC LICENSE Version 3
    To view a copy of this license, visit https://www.gnu.org/licenses/gpl-3.0.en.html
#>
param (
    [string]$settings_file = "$PSScriptRoot/settings.json",
    [switch]$dryrun = $false,
    [switch]$test = $false,
    [switch]$update = $false,
    [switch]$verbose = $false
     )

function Save-Settings()
{
    write-host "Saving settings to $settings_file"
    $global:settings.last_check = $current_time
    $settings | ConvertTo-Json|Out-File $settings_file
}
function Read-Settings()
{
    try {    
        if ([System.IO.File]::Exists($settings_file))
        {
            write-host "Loading settings from $settings_file"
            $global:settings = Get-Content $settings_file | ConvertFrom-Json
            if ([string]::IsNullOrEmpty($global:settings.last_check))
            {   
                Write-Host "last check not found, setting to now."
                $global:settings | Add-Member -NotePropertyMembers @{last_check=$current_time} -TypeName Asset -Force
            }
            if ([string]::IsNullOrEmpty($global:settings.last_exo))
            {   
                Write-Host "last exo seen time not found, setting to now."
                $global:settings | Add-Member -NotePropertyMembers @{last_exo=$current_time} -TypeName Asset -Force
            }
            if ([string]::IsNullOrEmpty($global:settings.reported_purge_time))
            {            
                Write-Host "db purge time not set, setting to 192 hours after last exo sighting."
                $global:settings | Add-Member -NotePropertyMembers @{reported_purge_time = 192} -TypeName Asset -Force
            }
            if ([string]::IsNullOrEmpty($global:settings.discord_webhook))
            {
                Write-Host "ERROR: Discord webhook is not set, I wont be able to send any alerts."
                write-host "Open $settings_file and set the discord_webhook setting."
                exit
            }

        } 
        else 
        {
            Save-Settings
            clear
            write-host "`r`n"
            write-host " File $settings_file created`r`n"
            write-host " ===========================SETUP REQUIRED============================="
            write-host " Open settings.json and set the discord_webhook.`r`n"
            write-host " Optionally, set the discord id to mention in posts. ex <@&1234567890>`r`n"
            write-host " this is found by typing \@groupname and hit enter in discord."
            write-host " ======================================================================"
            write-host "`r`n`r`n"            
            exit
        }
    } catch {
        Write-Host "An error occurred while attemping to read the settings file, there is probably a variable missing."
        Write-Host $_        
        exit
    }
}
Function Update-Planet($dataurl)
{
    Write-Host "Gathering data from"$dataurl
    
    $cancel_alert = $true
    $message_content = $global:settings.discord_mention

    #Get data for this specific planet
    $content = Invoke-RestMethod -Uri $dataurl
    write-host "Checking "$content.text_name 
    
    #0 math doesnt work for non programmer people
    $content.tier+=1
    
    #Send alert if this is a new exo
    if($global:settings.reported_initial -notcontains $content.id)
    {
        write-host $result.text_name "is NEW"
        $message_content +="`r`nA new exo planet has been sighted."
        $global:settings.reported_initial += $content.id
        $cancel_alert = $false
    }
    
    #Send alert if some one updated the image
    if(($settings.reported_image -notcontains $content.id) -and (-not [string]::IsNullOrEmpty($content.image_url)))
    {
            write-host $result.text_name "has a image."
            $message_content +="`r`nSurface image is avalible."
            $global:settings.reported_image += $content.id
            $cancel_alert = $false
    }
    
    #Send alert if we know what colors are avalible.
    Write-Host "Gathering data from"$content.block_colors_url
    $block_colors = Invoke-RestMethod -Uri $content.block_colors_url    
    if(($settings.reported_colors -notcontains $content.id) -and ($block_colors.block_colors.Count -gt 0))
    {
            
            write-host $result.text_name "has block colors avalible."
            $message_content +="`r`nResource colors are avalible."            
            $global:settings.reported_colors += $content.id
            $cancel_alert = $false
    }

    #Send alert if we have resourece data
    Write-Host "Gathering data from"($content.polls_url+"&limit=1")
    $poll_data = Invoke-RestMethod -Uri ($content.polls_url+"&limit=1")
    if( ($settings.reported_resources -notcontains $content.id) -and ($poll_data.count -gt 0))
    {
        write-host $result.text_name "has resource data."
        $message_content +="`r`nResource data is avalible."            
        $global:settings.reported_resources += $content.id
        $cancel_alert = $false
    }
    #script was called with -update so send this no matter what.
    if($update)
    {
        $message_content = "This message was requested manually, it may contain old information."
        $cancel_alert = $false
    }
    #If we dont have anything new to spam discord with then just dont both wasting resources with this planet anymore.    
    if($cancel_alert)
    {
        write-host $result.display_name "has no new updates, waiting till next cycle."
        return
    } 
    else 
    {
        write-host "Sending spam to discord for"$result.display_name
    }    


    $description = ""
    if(-not [string]::IsNullOrEmpty($content.assignment))
    {
        $description += "`r`nOrbiting: "+$content.assignment.text_name
    }    
    if (-not [string]::IsNullOrEmpty($content.start))
    {        
        $description +="`r`nStart "+(Get-Date -Date $content.start -Format "dddd MM/dd/yyyy HH:mm EST")
    }
    if (-not [string]::IsNullOrEmpty($content.end))
    {        
        $description +="`r`nEnd "+(Get-Date -Date $content.end -Format "dddd MM/dd/yyyy HH:mm EST")
    }

    #construct main embed
    $msg = [PSCustomObject]@{
        title=$content.text_name
        description=$description
        Scolor=7506394
        fields = @(   
        (Build-Custom-Field -name "Name" -value $content.text_name -inline "true"),    
        (Build-Custom-Field -name "Type" -value ("T"+$content.tier+" "+$content.world_type) -inline "true")
        
        )        
    }
    
    #Add liquid info if both surface and core are known.
    if ((-not [string]::IsNullOrEmpty($content.surface_liquid)) -and (-not [string]::IsNullOrEmpty($content.core_liquid)) )
    {    
        #:sweat_drops: :fire: 
        $msg.fields += (Build-Custom-Field -name "Liquid" -value (":arrow_up_small:  "+$content.surface_liquid+"`r`n:arrow_down_small:  "+$content.core_liquid) -inline "false")
    }
    
    #Add protection skill and points
    if (-not [string]::IsNullOrEmpty($content.protection_skill.name))
    {    
        $msg.fields += (Build-Custom-Field -name "Required Protection" -value ($content.protection_skill.name+" "+$content.protection_points) -inline "false")
    }

    #Add bestbow if present
    if (-not [string]::IsNullOrEmpty($content.bows.best))
    {    
        $msg.fields += (Build-Custom-Field -name "Best Bow(s)" -value ($content.bows.best -join ", ") -inline "false")
    }

    #Add sanctum image of planet if it exist as a thumbnail
    if (-not [string]::IsNullOrEmpty($content.image_url))
    {
        $imageorthumbnail="thumbnail"
        $d = @{$imageorthumbnail = [PSCustomObject]@{url = $content.image_url}}
        $msg | Add-Member -NotePropertyMembers $d -TypeName Asset
    }    
    #Add atlas image of planet as large image if atlas image exists.
    if (-not [string]::IsNullOrEmpty($content.atlas_image_url))
    {
        $imageorthumbnail="image"#"image" or "thumbnail"
        $d = @{$imageorthumbnail = [PSCustomObject]@{url = $content.atlas_image_url}}
        $msg | Add-Member -NotePropertyMembers $d -TypeName Asset
    }  
    #Add distance info, 1st distance is self warps, 2nd one should be the next closet planet.
    Write-Host "Gathering data from"($content.distances_url+"&limit=11&offset=0")
    $distances = (Invoke-RestMethod -Uri ($content.distances_url+"&limit=11&offset=0")).results|Where-Object {$_.distance -ne 0 -and $_.cost -ne 0 } |  Sort-Object distance
    if($distances.count -gt 0)
    {    
        #flip destination for any distances with mixed up paths.
        $distances | Foreach-Object { if ($_.world_source.text_name -ne $content.text_name) {$_.world_dest.text_name = $_.world_source.text_name} }
        
        $msg.fields += (Build-Custom-Field -name "Warp From" -value ($distances.world_dest.text_name -join "`r`n") -inline "true")
        $msg.fields += (Build-Custom-Field -name "Distance" -value ($distances.distance -join "`r`n") -inline "true")
        $msg.fields += (Build-Custom-Field -name "Cost" -value ($distances.cost -join "`r`n") -inline "true")
    }
 
    #Add forum url if avalible
    if (-not [string]::IsNullOrEmpty($content.forum_url))
    {
        #Add url to planet name
        $d = @{url=$content.forum_url}
        $msg | Add-Member -NotePropertyMembers $d -TypeName Asset
        #Add url as a link for people that need a link.
        $msg.fields += (Build-Custom-Field -name "Forum post" -value $content.forum_url -inline "false")
    }

   $payload = [PSCustomObject]@{
        username= "EXO ALERT"
        avatar_url= "https://i.imgur.com/sNN6P7F.png"#"https://i.imgur.com/q7lVpGo.png"
        content = $message_content
        embeds = @()+$msg
    }

    #Get the latest resouce data
    if($poll_data.count -gt 0)
    {
        Write-Host "Gathering data from"$poll_data.results.resources_url
        $latest_resource_poll = (Invoke-RestMethod -Uri ($poll_data.results.resources_url))        
        $payload.embeds += Build-ResourceTable -resources $latest_resource_poll.resources -time $poll_data.results.time
    }
    
    <#if (-not [string]::IsNullOrEmpty($content.forum_url))
    {        
        Write-Host "Adding forum link"
        $payload.embeds += Build-ForumLinkEmbed -url $content.forum_url
    }#>


    if (-not [string]::IsNullOrEmpty($content.start))
    {   
        Write-Host "Adding start timestamp"
        $payload.embeds += Build-TimeStampEmbed -date $content.start -text "Appeared"
    }

    if (-not [string]::IsNullOrEmpty($content.end))
    {   
        Write-Host "Adding end timestamp"
        $payload.embeds +=  Build-TimeStampEmbed -date $content.end -text "Departing" -exiting $true
    }

    if($dryrun)
    {
        $payload | ConvertTo-Json -Depth 100
    } 
    else 
    {
        Invoke-RestMethod -Uri $global:settings.discord_webhook -Method Post -Body ($payload | ConvertTo-Json -Depth 100) -ContentType 'application/json'

        If ($block_colors.block_colors.Count -gt 0)
        {   
            If(Build-ColorPalette -block_Colors  $block_colors  <#$content.block_colors_url#> -OutFile "$PSScriptRoot/color-palette.png" -Title ("Color Preview for "+$content.text_name) ) #("$home/"+$content.id+".png")
            {
                $result = Publish-Discord -imgPath "$PSScriptRoot/color-palette.png" -WebHookUrl $global:settings.discord_webhook
                write-host ($result.attachments.filename) ($result.attachments.size).ToString('N0')"KB uploaded to"($result.attachments.url)
            }
        }
    }
}
Function Build-ResourceTable
{
    param ($resources,$time)
    $block_names = Get-Content $PSScriptRoot/blocks.json |ConvertFrom-Json
    $utc = (Get-Date -Date $time).ToUniversalTime()
    $table = @()
    $resources|Sort-Object count -Descending | Foreach-Object {
        $table +=[pscustomobject]@{                        
            name=($block_names.($_.item.game_id) + " (" + $_.item.game_id + ")")
            item_name=($_.item.name)
            game_id=$_.item.game_id
            total=[string]::Format('{0:N0}',$_.count)
            percentage=($_.percentage+"%")
        }
    }

    [PSCustomObject]@{
        title="Planetary Resource Survey"
        fields = @( (Build-Custom-Field -name "Resource" -value ($table.name -join "`r`n") -inline "true"),
                    (Build-Custom-Field -name "Count" -value ($table.total -join "`r`n") -inline "true"),
                    (Build-Custom-Field -name "%" -value ($table.percentage -join "`r`n") -inline "true")
                )
        timestamp = (Get-Date -Format "o" -Date $utc)
        footer = [PSCustomObject]@{
            text = "as of"
            icon_url= "https://i.imgur.com/sRbhlRi.png"
        }
    }
}
Function Build-ForumLinkEmbed
{
    param([string]$url)
    [PSCustomObject]@{  
        title = "Boundless Forum Post"    
        description = $url
        footer = [PSCustomObject]@{
            icon_url= "https://i.imgur.com/iBC6DJ2.png"
        }
        thumbnail = [PSCustomObject]@{url = "https://i.imgur.com/iBC6DJ2.png"}
    }
}
Function Build-TimeStampEmbed
{
    param ([string]$text = "err",[string]$date = "2100-01-01T01:01:01",[bool]$exiting=$false)
    $icon = "https://i.imgur.com/v3DWRmu.png"
    if($exiting){$icon = "https://i.imgur.com/4eEfjxH.png"}
    $time = (Get-Date -date $date -Format "dddd MM/dd/yyyy HH:mm K")+"US-EST"
    $utc = (Get-Date -Date $date).ToUniversalTime()
    $pst = (Get-Date -date $date).AddHours(-3)    
    $time += "`r`n"+(Get-Date -date $pst -Format "dddd MM/dd/yyyy HH:mm K")+"US-PST"
    $time += "`r`n"+(Get-Date -date $utc -Format "dddd MM/dd/yyyy HH:mm K")+"-UTC"
    [PSCustomObject]@{  
        title = $text      
        description = $time
        timestamp = (Get-Date -Format "o" -Date $utc)
        footer = [PSCustomObject]@{
            text = "Your local time->"
            icon_url= $icon
        }
        thumbnail = [PSCustomObject]@{url = "https://i.imgur.com/sRbhlRi.png"}
    }
}
Function Build-ImageEmbed
{
    param ([string]$url = "err")
    [PSCustomObject]@{        
        image = [PSCustomObject]@{
            url = $url
        }
    }
}
Function Build-Custom-Field
{
param (
    [string]$name = "name",
    [string]$value = "value",
    [string]$inline = "false"
     )

    [PSCustomObject]@{
        name=$name
        value=$value
        inline=$inline
        }
}

Function Build-ColorPalette()
{    
    param ($block_Colors,[string]$OutFile,[string]$Title)

    #Strings
    $block_names = Get-Content $PSScriptRoot/blocks.json |ConvertFrom-Json
    $color_names = Get-Content $PSScriptRoot/colors.json |ConvertFrom-Json
    $color_rgb = Get-Content $PSScriptRoot/color-mappings-rgb.json |ConvertFrom-Json


    
    ##Settings
    $rowwidth = 200
    $rowheight = 30
    $y_offset = 5  

    #Color palette File
    $filewidth = $rowwidth * 4    
    $fileheight = (&{ if ($block_Colors.block_colors.count -gt 0){$rowheight * ($block_Colors.block_colors.count+2)} else {$rowheight*3} })

    #Font
    $font = new-object System.Drawing.Font Consolas,10 
    
    ##Background color
    $brushBg = [System.Drawing.Brushes]::Black 
    
    ##Forground color
    $brushFg = [System.Drawing.Brushes]::White
    $brushGray = [System.Drawing.Brushes]::Gray

    $bmp = new-object System.Drawing.Bitmap $filewidth,$fileheight 
    $graphics = [System.Drawing.Graphics]::FromImage($bmp) 
    
    #Fill image with background color
    $graphics.FillRectangle($brushBg,0,0,$bmp.Width,$bmp.Height)

    $graphics.DrawString($Title,$font,$brushFg,10 ,$y_offset) 

    ##
    $row=1
    if ($block_Colors.block_colors.count -gt 0)
    {
        
        foreach($color in $block_Colors.block_colors ) 
        {
        ##
            $img_name = $block_names.($color.item.game_id)
            $img_color= $color_names.($color.color.game_id)
            $img_rgb = $color_rgb.($color.color.game_id)

            #Color on right
            $c2 = [System.Drawing.SolidBrush]::New([System.Drawing.Color]::FromArgb(255,$img_rgb[0],$img_rgb[1],$img_rgb[2]))
            $graphics.FillRectangle($c2,$rowwidth*2,0+($row*$rowheight),$rowwidth,$rowheight) 

            #Text on left
            $graphics.DrawString($img_name,$font,$brushFg,10 ,$y_offset+($row*$rowheight)) 

            #Text in middle
            $graphics.DrawString($img_color+" ("+$color.color.game_id+")",$font,$brushFg,10+$rowwidth ,$y_offset+($row*$rowheight)) 

            $color_source = ""
            if($color.is_exo_only)
            {
                $color_source = "XO"
                if($color.is_new)
                {
                    $color_source += " NEW COLOR!!"
                } else {
                    if([string]::IsNullOrEmpty($color.days_since_exo))
                        {
                            $color.days_since_exo = "many"
                        }
                    $color_source +=" seen "+$color.days_since_exo+" days ago"
                }
            } 
            elseif ($color.is_sovereign_only) 
            {
                $color_source = $color.first_world.text_name
            } 
            else 
            {
                $color_source = $color.first_world.text_name
            }
            (&{  if($color.is_exo_only){$brushFg}else{$brushGray}  })
            #Text on right
            $graphics.DrawString($color_source,$font,(&{  if($color.is_exo_only){$brushFg}else{$brushGray}  }),10 +($rowwidth*3) ,$y_offset+($row*$rowheight)) 

            $row +=1
        ##
        }
    } 
    else {
        ##Something went wrong and we didn't recive and colors.. +($rowheight*2)
            $graphics.DrawString("ERROR",$font,$brushFg,10 ,$y_offset+(2*$rowheight)) 
            $graphics.DrawString('No Data Recived',$font,$brushFg,10+$rowwidth,$y_offset+(2*$rowheight)) 

            $row +=1
    }

    $graphics.DrawString("image created by Emareks ExoAlert, Viking Guild https://discord.gg/yf5YkB6a56",$font,$brushGray,10,$y_offset+($rowheight*($row))) 
    ##

    $graphics.Dispose() 
    $bmp.Save($OutFile) 

    #Invoke-Item $OutFile 
    [System.IO.File]::Exists($OutFile)
}

class DiscordFile {

    [string]$FilePath                                  = [string]::Empty
    [string]$FileName                                  = [string]::Empty
    [string]$FileTitle                                 = [string]::Empty
    [System.Net.Http.MultipartFormDataContent]$Content = [System.Net.Http.MultipartFormDataContent]::new()
    [System.IO.FileStream]$Stream                      = $null

    DiscordFile([string]$FilePath)
    {
        $this.FilePath  = $FilePath
        $this.FileName  = Split-Path $filePath -Leaf
        $this.fileTitle = $this.FileName.Substring(0,$this.FileName.LastIndexOf('.'))
        $fileContent = $this.GetFileContent($FilePath)
        $this.Content.Add($fileContent)                 
    }

    [System.Net.Http.StreamContent]GetFileContent($filePath)
    {        
        $fileStream                             = [System.IO.FileStream]::new($filePath, [System.IO.FileMode]::Open)
        $fileHeader                             = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
        $fileHeader.Name                        = $this.fileTitle
        $fileHeader.FileName                    = $this.FileName
        $fileContent                            = [System.Net.Http.StreamContent]::new($fileStream)        
        $fileContent.Headers.ContentDisposition = $fileHeader
        $fileContent.Headers.ContentType        = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("text/plain")   
                        
        $this.stream = $fileStream
        return $fileContent        
    }    
}          
Function Publish-Discord
{
    param ([string]$imgPath,[string]$WebHookUrl)
    $fileInfo = [DiscordFile]::New($imgPath)    
    $payload  = $fileInfo.Content
    try {    
        $reply = Invoke-RestMethod -Uri $WebHookUrl -Body $payload -Method Post
    }
    catch {
    
        $errorMessage = $_.Exception.Message
        throw "Error executing Discord Webhook -> [$errorMessage]!"
    }
    finally {
    $fileInfo.Stream.Dispose()                    
    }
 $reply
}
Function Publish-Imgur
{
    param ([string]$imgPath,[string]$ClientID)
    Add-Type -AssemblyName System.Net.Http
    $imgInBase64 = [convert]::ToBase64String((get-content $imgPath -encoding byte))
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Client-ID $ClientID")
    $body = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $body.Add("image", $imgInBase64)
    try {
        $response=Invoke-RestMethod 'https://api.imgur.com/3/image' -Method 'POST' -Headers $headers -Body $body    
    }
    catch {
    
        $errorMessage = $_.Exception.Message
        throw "Error executing imgur Webhook -> [$errorMessage]!"   
    }
    $response.data.link
}

<#
    MAIN()
#>

#BoundlessAPI URI for exo planets 
$prodexouri="https://api.boundlexx.app/api/v1/worlds/simple?format=json&is_exo=true&limit=10&offset=0"

if($test){
    #test BoundlessAPI URI for exo planets, distances dont work but everthing else should pop.
    $prodexouri = "https://api.boundlexx.app/api/v1/worlds/simple/?format=json&is_exo=true&limit=1&offset=216&active=false"
}

$current_time = Get-Date -Format "dddd MM/dd/yyyy HH:mm K"

write-host "Checking for exo planets $current_time"
Write-Host "Gathering data data URI:( $prodexouri )"

$response = ""
try {
    $response = Invoke-RestMethod -Uri $prodexouri     
}
catch {
    Write-Host "An error occurred while attemping to fetch exo data from $prodexouri"
    Write-Host $_
    Write-Host "Nothing to check because i'm receiving no data, exiting."
    exit
}



$global:settings = [PSCustomObject]@{
    reported_initial = @()
    reported_image = @()
    reported_colors = @()
    reported_resources = @()
    last_check=$current_time
    last_exo=$current_time
    discord_webhook=""
    discord_mention=""
    reported_purge_time = 192
}

Read-Settings
if(($response.results.count -eq 0) -or ($null -eq $response.results) ) 
{
    $wipeat = 192
    if($global:settings.reported_purge_time -gt 1){
        $wipeat = $global:settings.reported_purge_time
    }
    $lastexohrs = (NEW-TIMESPAN –Start $settings.last_exo –End $current_time).Hours
    write-host "No exo planets in the sky, last sighting was $lastexohrs hours ago, exiting!"
    if(($lastexohrs -gt $wipeat) -and ($settings.reported_initial.Count -gt 0))
    {
        write-host "No exos have been sighted in the last $wipeat hours, wiping report data."
        $global:settings.reported_initial = @()
        $global:settings.reported_image = @()
        $global:settings.reported_colors = @()
        $global:settings.reported_resources = @()
    }
    Save-Settings
    exit
} 
else 
{
    $global:settings.last_exo = $current_time
    if($update)
    {
        write-host "Sending update of all active exos to webhook"} 
    else {
        write-host "Active exo planet, checking if an alert needs to be sent"
    }
}

foreach($result in $response.results){
    write-host $result.id $result.text_name "Tier"($result.tier+1) $result.world_type 
    if(($settings.reported_initial -notcontains $result.id) -or ($settings.reported_image -notcontains $result.id) -or ($settings.reported_colors -notcontains $result.id) -or $update)
    {
        Update-Planet($result.url)
    } else {
        write-host $result.text_name "has already been fully reported. No more alerts will be sent."
    }   

}

if((-not $test) -and (-not $dryrun))
{
    Save-Settings
}
write-host "done" $settings.last_check
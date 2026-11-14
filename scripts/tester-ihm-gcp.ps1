# Issue #96 — Test de l'IHM de la VM DEV (Claude)
# Ouvre l'IHM déployée sur la VM GCP DEV (privée) dans Chrome, via un tunnel SSH IAP.
#   powershell -ExecutionPolicy Bypass -File scripts\tester-ihm-gcp.ps1
#   ... -Projet mer-boussole-dev -Zone europe-west9-a -Vm boussole-dev -PortLocal 8443
# Étapes : contrôles (gcloud, compte, projet, VM, SSH IAP, conteneurs, réponse HTTPS sur la VM),
# résumé, validation (O/N), puis tunnel + Chrome. Entrée ferme le tunnel à la fin.
# Rien n'est modifié sur la VM, sauf son démarrage si elle est arrêtée et que vous l'acceptez.
param(
    [string]$Projet = "mer-boussole-dev",
    [string]$Zone = "europe-west9-a",
    [string]$Vm = "boussole-dev",
    [int]$PortLocal = 8443
)

$ErrorActionPreference = "Stop"
$global:erreurs = 0
$global:alertes = 0

function Etape([string]$titre) { Write-Host "`n==> $titre" -ForegroundColor Cyan }
function Ok([string]$texte) { Write-Host "  [OK] $texte" -ForegroundColor Green }
function Alerte([string]$texte) { Write-Host "  [!]  $texte" -ForegroundColor Yellow; $global:alertes++ }
function Ko([string]$texte) { Write-Host "  [X]  $texte" -ForegroundColor Red; $global:erreurs++ }
function Arret([string]$texte) { Ko $texte; Write-Host "`nContrôles interrompus : corriger le point ci-dessus puis relancer le script." -ForegroundColor Red; exit 1 }

# gcloud.cmd plutôt que gcloud.ps1 : PowerShell supprime certains arguments (« -- ») passés aux scripts .ps1.
$gcloud = (Get-Command gcloud.cmd -ErrorAction SilentlyContinue).Source
function G([string[]]$arguments) {
    $ErrorActionPreference = "Continue"   # PowerShell 5.1 : sinon le moindre message gcloud sur stderr arrête le script
    $sortie = & $gcloud @arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Texte = (($sortie | ForEach-Object { "$_" }) -join "`n").Trim() }
}
$cible = @("--project=$Projet", "--zone=$Zone")

Etape "Outils sur ce PC"
if (-not $gcloud) { Arret "SDK Google Cloud introuvable (gcloud.cmd). Rouvrir le terminal après l'installation, ou l'ajouter au PATH." }
Ok "gcloud : $gcloud"
$chrome = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($chrome) { Ok "Chrome : $chrome" } else { Arret "Google Chrome introuvable." }
$occupe = Get-NetTCPConnection -LocalPort $PortLocal -State Listen -ErrorAction SilentlyContinue
if ($occupe) { Arret "Le port local $PortLocal est déjà utilisé (un ancien tunnel ?). Le libérer ou relancer avec -PortLocal 9443." }
Ok "Port local $PortLocal libre"

Etape "Compte Google et projet"
$compte = (G @("auth", "list", "--filter=status:ACTIVE", "--format=value(account)")).Texte
if (-not $compte) {
    Alerte "Aucun compte connecté : ouverture de la connexion Google dans le navigateur."
    & $gcloud auth login
    $compte = (G @("auth", "list", "--filter=status:ACTIVE", "--format=value(account)")).Texte
    if (-not $compte) { Arret "Connexion Google non effectuée." }
}
Ok "Compte actif : $compte"
$r = G @("projects", "describe", $Projet, "--format=value(lifecycleState)")
if ($r.Code -ne 0) { Arret "Projet $Projet inaccessible avec ce compte :`n$($r.Texte)" }
if ($r.Texte -ne "ACTIVE") { Arret "Projet $Projet dans l'état $($r.Texte)." }
Ok "Projet $Projet actif"

Etape "Machine virtuelle $Vm"
$r = G (@("compute", "instances", "describe", $Vm, "--format=value(status)") + $cible)
if ($r.Code -ne 0) { Arret "VM $Vm introuvable dans $Zone (Terraform DEV appliqué ? API Compute activée ?) :`n$($r.Texte)" }
$etat = $r.Texte
if ($etat -ne "RUNNING") {
    Alerte "La VM est dans l'état $etat."
    if ((Read-Host "  Démarrer la VM maintenant ? (O/N)") -notmatch '^[oO]') { Arret "VM non démarrée." }
    $r = G (@("compute", "instances", "start", $Vm) + $cible)
    if ($r.Code -ne 0) { Arret "Démarrage impossible :`n$($r.Texte)" }
    Start-Sleep -Seconds 30   # le temps que SSH et Docker démarrent
}
Ok "VM en marche"

Etape "Connexion SSH via IAP et état de l'application sur la VM"
Write-Host "  (première fois : gcloud peut créer une clé SSH et poser des questions, répondre dans cette fenêtre)"
# Script exécuté sur la VM, transmis en base64 pour éviter les problèmes de guillemets PowerShell -> cmd -> plink.
$distant = @'
D=docker; docker info >/dev/null 2>&1 || D="sudo -n docker"
command -v docker >/dev/null || { echo "DOCKER=absent"; exit 0; }
$D info >/dev/null 2>&1 && echo "DOCKER=ok" || { echo "DOCKER=inaccessible"; exit 0; }
for s in db api web; do
  id=$($D ps -aq --filter "label=com.docker.compose.service=$s" | head -1)
  if [ -z "$id" ]; then echo "SERVICE_$s=absent"; continue; fi
  echo "SERVICE_$s=$($D inspect --format '{{.State.Status}}' "$id")"
  echo "ETAT_$s=$($D ps -a --filter "id=$id" --format '{{.Status}} | ports : {{.Ports}}')"
  # Journaux des conteneurs qui ne tournent pas, ou qui redémarrent en boucle, encodés sur une ligne.
  if [ "$($D inspect --format '{{.State.Status}} {{.RestartCount}}' "$id")" != "running 0" ]; then
    echo "LOGS_$s=$($D logs --tail 25 "$id" 2>&1 | base64 -w0)"
  fi
done
web=$($D ps -aq --filter "label=com.docker.compose.service=web" | head -1)
dom=""
[ -n "$web" ] && dom=$($D inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$web" | sed -n 's/^PKP_DOMAINE=//p')
echo "DOMAINE=$dom"
# Adresse Caddy : [http(s)://][hôte][:port]. Sans schéma : HTTP si le port est 80, HTTPS sinon (comme Caddy).
d=$(echo "${dom%%,*}" | tr -d ' '); sch=""
case "$d" in http://*) sch=http; d=${d#http://};; https://*) sch=https; d=${d#https://};; esac
d=${d%%/*}
case "$d" in *:*) h=${d%:*}; p=${d##*:};; *) h=$d; p="";; esac
[ -z "$sch" ] && { [ "$p" = "80" ] && sch=http || sch=https; }
[ -z "$p" ] && { [ "$sch" = "http" ] && p=80 || p=443; }
echo "SCHEMA=$sch"; echo "HOTE=$h"; echo "PORT=$p"
H=${h:-localhost}
# Port de la VM sur lequel Docker publie le port $p du conteneur web (souvent identique, pas toujours).
hp=$p
if [ -n "$web" ]; then
  pub=$($D port "$web" "$p/tcp" 2>/dev/null | head -1)
  echo "PUBLIE=$pub"
  [ -n "$pub" ] && hp=${pub##*:}
fi
echo "PORT_VM=$hp"
echo "ECOUTE=$( (ss -ltn 2>/dev/null || sudo -n ss -ltn) | awk 'NR>1{n=split($4,a,":"); print a[n]}' | sort -un | tr '\n' ' ')"
if [ -n "$web" ]; then
  if [ "$sch" = "http" ]; then
    page=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H "Host: $H" "http://127.0.0.1:$hp/" 2>&1 | tr '\n' ' ')
    api=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -H "Host: $H" "http://127.0.0.1:$hp/api/health" 2>&1 | tr '\n' ' ')
  else
    page=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$H:$hp:127.0.0.1" "https://$H:$hp/" 2>&1 | tr '\n' ' ')
    api=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 15 --resolve "$H:$hp:127.0.0.1" "https://$H:$hp/api/health" 2>&1 | tr '\n' ' ')
    echo "CERT=$(echo | openssl s_client -connect "127.0.0.1:$hp" -servername "$H" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | head -1)"
  fi
  echo "HTTP_PAGE=$page"; echo "HTTP_API=$api"
  # Page en échec : journal de Caddy (conteneur web) et de l'API pour comprendre pourquoi.
  case "$page" in *200) ;; *)
    echo "LOGS_web=$($D logs --tail 25 "$web" 2>&1 | base64 -w0)"
    a=$($D ps -aq --filter "label=com.docker.compose.service=api" | head -1)
    [ -n "$a" ] && echo "LOGS_api=$($D logs --tail 25 "$a" 2>&1 | base64 -w0)";;
  esac
fi
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($distant -replace "`r", "")))
$sortie = & $gcloud compute ssh $Vm @cible --tunnel-through-iap --command "echo $b64 | base64 -d | bash"
if ($LASTEXITCODE -ne 0) {
    Arret "SSH via IAP impossible. Vérifier les rôles IAP (roles/iap.tunnelResourceAccessor) et OS Login (roles/compute.osLogin) de $compte, et la règle de pare-feu boussole-dev-iap-ssh."
}
Ok "SSH via IAP fonctionnel"
$infos = @{}
foreach ($ligne in $sortie) { if ("$ligne" -match '^([A-Z_a-z]+)=(.*)$') { $infos[$Matches[1]] = $Matches[2].Trim() } }

switch ($infos["DOCKER"]) {
    "ok" { Ok "Docker présent sur la VM" }
    "absent" { Arret "Docker n'est pas installé sur la VM : l'application n'y est pas encore déployée (voir docs/DEPLOIEMENT.md)." }
    default { Arret "Docker inaccessible sur la VM (droits sudo de votre compte OS Login ?)." }
}
$enPanne = $false
foreach ($s in "db", "api", "web") {
    $etatS = $infos["SERVICE_$s"]
    if ($etatS -eq "running" -and $infos["ETAT_$s"] -notmatch "Restarting") {
        Ok "Conteneur $s en marche ($($infos["ETAT_$s"]))"
    } elseif ($etatS -eq "absent") {
        Ko "Conteneur $s absent (sur la VM, dans deploy/ : docker compose up -d)"; $enPanne = $true
    } else {
        Ko "Conteneur $s : $etatS ($($infos["ETAT_$s"]))"; $enPanne = $true
    }
    if ($infos["LOGS_$s"]) {
        Write-Host "       Dernières lignes du journal de $s :" -ForegroundColor DarkGray
        $texte = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($infos["LOGS_$s"]))
        $texte -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "       | $_" -ForegroundColor DarkGray }
    }
}
if ($enPanne) { Arret "Application incomplète sur la VM : voir l'état et les journaux ci-dessus." }

$domaine = $infos["DOMAINE"]
$schema = $infos["SCHEMA"]; $hote = $infos["HOTE"]; $portDistant = $infos["PORT_VM"]
Ok "Adresse Caddy (PKP_DOMAINE) : '$domaine' -> $schema, port $($infos["PORT"]) dans le conteneur web"
if ($infos["PUBLIE"]) { Ok "Port publié sur la VM : $($infos["PUBLIE"])" } else { Ko "Le port $($infos["PORT"]) du conteneur web n'est pas publié sur la VM (section ports: du docker-compose.yml utilisé)" }
Write-Host "  Ports en écoute sur la VM : $($infos["ECOUTE"])"
if ($infos["HTTP_PAGE"] -match '200$') { Ok "Page d'accueil : HTTP 200" } else { Ko "Page d'accueil : $($infos["HTTP_PAGE"]) (000 = pas de réponse)" }
if ($infos["HTTP_API"] -match '200$') { Ok "API (/api/health) : HTTP 200" } else { Ko "API (/api/health) : $($infos["HTTP_API"])" }
if ($schema -eq "https") {
    if ($infos["CERT"]) { Ok "Certificat : $($infos["CERT"])" } else { Alerte "Aucun certificat lu : avec un vrai domaine sur une VM privée, Let's Encrypt échoue ; mettre PKP_DOMAINE=localhost dans deploy/.env sur la VM." }
}

# Chrome est lancé avec un profil dédié (hors de votre profil habituel) :
# - un vrai nom de domaine est redirigé vers le tunnel local, sans toucher au fichier hosts ;
# - les erreurs de certificat sont ignorées (certificat auto-signé de Caddy) dans ce profil seulement.
if (-not $hote -or $hote -eq "localhost") {
    $url = "$($schema)://localhost:$PortLocal/"
    $regles = $null
} else {
    $url = "$($schema)://$hote/"
    $regles = "--host-resolver-rules=MAP $hote 127.0.0.1:$PortLocal"
}
$profil = Join-Path $env:TEMP "boussole-test-ihm-chrome"

Etape "Résumé"
Write-Host "  Compte  : $compte"
Write-Host "  Cible   : $Vm ($Projet, $Zone)"
Write-Host "  Tunnel  : localhost:$PortLocal -> $($Vm):$portDistant (SSH via IAP)"
Write-Host "  Adresse : $url  (élève : /eleve, professeur : /enseignant, administration : /admin)"
Write-Host "  Chrome  : profil de test dédié ($profil)"
if ($global:erreurs -gt 0) {
    Write-Host "`n  $($global:erreurs) contrôle(s) en échec : l'IHM risque de ne pas s'afficher correctement." -ForegroundColor Red
} elseif ($global:alertes -gt 0) {
    Write-Host "`n  Tous les contrôles bloquants sont passés ($($global:alertes) alerte(s))." -ForegroundColor Yellow
} else {
    Write-Host "`n  Tous les contrôles sont passés." -ForegroundColor Green
}
if ((Read-Host "`nOuvrir le tunnel et lancer Chrome ? (O/N)") -notmatch '^[oO]') { Write-Host "Abandon, rien n'a été lancé."; exit 0 }

Etape "Ouverture du tunnel"
$journal = Join-Path $env:TEMP "boussole-tunnel"
$argsTunnel = "compute ssh $Vm --project=$Projet --zone=$Zone --tunnel-through-iap --ssh-flag=-N --ssh-flag=`"-L $($PortLocal):localhost:$($portDistant)`""
$tunnel = Start-Process -FilePath $gcloud -ArgumentList $argsTunnel -NoNewWindow -PassThru `
    -RedirectStandardOutput "$journal.out.log" -RedirectStandardError "$journal.err.log"
$pret = $false
for ($i = 0; $i -lt 60 -and -not $tunnel.HasExited; $i++) {
    Start-Sleep -Seconds 1
    $client = New-Object Net.Sockets.TcpClient
    try { $client.Connect("127.0.0.1", $PortLocal); $pret = $true } catch { } finally { $client.Close() }
    if ($pret) { break }
}
if (-not $pret) {
    if (-not $tunnel.HasExited) { & taskkill /PID $tunnel.Id /T /F | Out-Null }
    Write-Host (Get-Content "$journal.err.log" -Raw -ErrorAction SilentlyContinue)
    Arret "Le tunnel ne s'est pas ouvert en 60 s (journal ci-dessus : $journal.err.log)."
}
Ok "Tunnel ouvert sur localhost:$PortLocal"

Etape "Lancement de Chrome"
$argsChrome = @("--user-data-dir=`"$profil`"", "--ignore-certificate-errors", "--no-first-run", "--new-window")
if ($regles) { $argsChrome += "`"$regles`"" }
$argsChrome += $url
Start-Process -FilePath $chrome -ArgumentList $argsChrome
Ok "Chrome ouvert sur $url"
Write-Host "  Comptes de test : ceux créés sur la VM (les codes de démo de api/app/db/seed.py ne valent que si la base de démo y a été chargée)."

Read-Host "`nTester l'IHM, puis appuyer sur Entrée ici pour fermer le tunnel"
if (-not $tunnel.HasExited) { & taskkill /PID $tunnel.Id /T /F | Out-Null }
Ok "Tunnel fermé"

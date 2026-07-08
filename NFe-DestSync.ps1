<#
    ConverterXML.ps1
    Versao: 1.0.0

    Parte 1:
    - Parametros iniciais
    - Estrutura de pastas
    - Caminhos relativos ao script/exe
    - Leitura do config.json
    - Logger CSV
    - Busca dos arquivos XML
    - Resumo inicial
    - Modo DryRun

    Estrutura esperada:

    ConvertXML\
    |-- ConverterXML.ps1
    |-- ConverterXML.exe
    |-- config.json
    |-- README.txt
    |-- XML\
    |   |-- Entrada\
    |   |-- Convertidos\
    |   |-- Backup\
    |   |-- Processados\
    |-- Logs\
#>

param(
    [switch]$DryRun
)

Set-StrictMode -Version 2.0

# =========================
# CONFIGURACOES GLOBAIS
# =========================

$script:AppName = "Converter XML"
$script:AppVersion = "1.0.0"

$script:Summary = @{
    ArquivosEncontrados = 0
    Convertidos         = 0
    JaEramArte          = 0
    Duplicados          = 0
    Desconhecidos       = 0
    Ignorados           = 0
    Erros               = 0
}

# =========================
# FUNCOES DE BASE
# =========================

function Get-ApplicationRoot {
    <#
        Retorna a pasta raiz da aplicacao.

        Compativel com:
        - execucao como .ps1
        - execucao como .exe gerado pelo ps2exe

        Todos os caminhos do sistema devem partir daqui.
    #>

    try {
        if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) {
            return $PSScriptRoot
        }

        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        return Split-Path -Parent $exePath
    }
    catch {
        throw "Nao foi possivel identificar a pasta raiz da aplicacao. Erro: $($_.Exception.Message)"
    }
}

function Initialize-Paths {
    <#
        Cria e centraliza todos os caminhos utilizados pela aplicacao.

        Nova estrutura:

        ConvertXML\
        |-- ConverterXML.ps1
        |-- ConverterXML.exe
        |-- config.json
        |-- README.txt
        |-- XML\
        |   |-- Entrada\
        |   |-- Convertidos\
        |   |-- Backup\
        |   |-- Processados\
        |-- Logs\

        Observacao:
        O nome da pasta raiz pode ser ConvertXML, ConverterXML ou qualquer outro.
        O programa sempre usa a pasta onde o script/exe esta sendo executado.
    #>

    $root = Get-ApplicationRoot
    $xmlRoot = Join-Path $root "XML"

    $script:Paths = @{
        Root        = $root
        XmlRoot     = $xmlRoot
        Entrada     = Join-Path $xmlRoot "Entrada"
        Xml         = Join-Path $xmlRoot "Entrada"
        Convertidos = Join-Path $xmlRoot "Convertidos"
        Backup      = Join-Path $xmlRoot "Backup"
        Processados = Join-Path $xmlRoot "Processados"
        Logs        = Join-Path $root "Logs"
        Config      = Join-Path $root "config.json"
    }
}

function Initialize-Folders {
    <#
        Garante que todas as pastas obrigatorias existam.
        Caso alguma pasta nao exista, ela sera criada automaticamente.
    #>

    $folders = @(
        $script:Paths.XmlRoot,
        $script:Paths.Entrada,
        $script:Paths.Convertidos,
        $script:Paths.Backup,
        $script:Paths.Processados,
        $script:Paths.Logs
    )

    foreach ($folder in $folders) {
        try {
            if (-not (Test-Path -LiteralPath $folder)) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
        }
        catch {
            throw "Erro ao criar/verificar pasta '$folder'. Erro: $($_.Exception.Message)"
        }
    }
}

function Load-Configuration {
    <#
        Carrega o arquivo config.json.

        Nesta primeira parte, apenas validamos se ele existe
        e se e um JSON valido.

        Nas proximas etapas, validaremos os dados da empresa destino.
    #>

    try {
        if (-not (Test-Path -LiteralPath $script:Paths.Config)) {
            throw "Arquivo config.json nao encontrado em: $($script:Paths.Config)"
        }

        $jsonText = Get-Content -LiteralPath $script:Paths.Config -Raw -Encoding UTF8
        $config = $jsonText | ConvertFrom-Json

        return $config
    }
    catch {
        throw "Erro ao carregar config.json. Erro: $($_.Exception.Message)"
    }
}

function Initialize-LogFile {
    <#
        Cria o arquivo de log CSV do dia.

        Formato:
        Logs\AAAA-MM-DD.csv

        Separador:
        Ponto e virgula, para facilitar abertura no Excel em ambiente PT-BR.

        Encoding:
        UTF-8 sem BOM para evitar caracteres extras no arquivo.
    #>

    $date = Get-Date -Format "yyyy-MM-dd"
    $script:LogFile = Join-Path $script:Paths.Logs "$date.csv"

    try {
        if (-not (Test-Path -LiteralPath $script:LogFile)) {
            $header = "Data;Hora;Arquivo;Resultado;Empresa;TempoMs;Mensagem"

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

            [System.IO.File]::WriteAllText(
                $script:LogFile,
                $header + [Environment]::NewLine,
                $utf8NoBom
            )
        }
    }
    catch {
        throw "Erro ao criar arquivo de log. Erro: $($_.Exception.Message)"
    }
}

function Escape-CsvValue {
    <#
        Limpa valores antes de inserir no CSV simples separado por ponto e virgula.

        Esta funcao evita que quebras de linha ou ponto e virgula
        quebrem a estrutura do log.
    #>

    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ($Value -replace ";", "," -replace "`r|`n", " ")
}

function Write-Log {
    <#
        Registra uma linha no log CSV.

        Campos:
        Data;Hora;Arquivo;Resultado;Empresa;TempoMs;Mensagem
    #>

    param(
        [string]$Arquivo,
        [string]$Resultado,
        [string]$Empresa,
        [long]$TempoMs,
        [string]$Mensagem
    )

    try {
        $now = Get-Date

        $safeArquivo = Escape-CsvValue -Value $Arquivo
        $safeResultado = Escape-CsvValue -Value $Resultado
        $safeEmpresa = Escape-CsvValue -Value $Empresa
        $safeMensagem = Escape-CsvValue -Value $Mensagem

        $line = "{0};{1};{2};{3};{4};{5};{6}" -f @(
            $now.ToString("yyyy-MM-dd"),
            $now.ToString("HH:mm:ss"),
            $safeArquivo,
            $safeResultado,
            $safeEmpresa,
            $TempoMs,
            $safeMensagem
        )

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        [System.IO.File]::AppendAllText(
            $script:LogFile,
            $line + [Environment]::NewLine,
            $utf8NoBom
        )
    }
    catch {
        Write-Warning "Nao foi possivel registrar log: $($_.Exception.Message)"
    }
}

function Get-XmlFiles {
    <#
        Retorna apenas arquivos .xml da pasta XML\Entrada.

        Importante:
        - nao busca subpastas
        - nao carrega conteudo do arquivo
        - processa arquivo por arquivo futuramente
    #>

    try {
        if (-not (Test-Path -LiteralPath $script:Paths.Entrada)) {
            return @()
        }

        return @(Get-ChildItem -LiteralPath $script:Paths.Entrada -File -Filter "*.xml")
    }
    catch {
        throw "Erro ao buscar arquivos XML em XML\Entrada. Erro: $($_.Exception.Message)"
    }
}

function Test-ConvertedExists {
    <#
        Verifica se ja existe um arquivo com o mesmo nome na pasta Convertidos.
        Se existir, o XML nao devera ser processado novamente.
    #>

    param(
        [System.IO.FileInfo]$File
    )

    $convertedPath = Join-Path $script:Paths.Convertidos $File.Name
    return Test-Path -LiteralPath $convertedPath
}

function Show-Header {
    <#
        Exibe o cabecalho visual da aplicacao.
        Os textos foram mantidos sem acentos para evitar problemas no console do PowerShell 5.1.
    #>

    Clear-Host

    Write-Host "====================================="
    Write-Host $script:AppName
    Write-Host "Versao: $script:AppVersion"
    Write-Host "====================================="
    Write-Host ""

    if ($DryRun) {
        Write-Host "MODO TESTE ATIVO: nenhum arquivo sera gravado." -ForegroundColor Yellow
        Write-Host ""
    }
}

function Show-Summary {
    <#
        Exibe o resumo final da execucao.
    #>

    param(
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    Write-Host ""
    Write-Host "====================================="
    Write-Host "Converter XML"
    Write-Host ""
    Write-Host "Arquivos encontrados: $($script:Summary.ArquivosEncontrados)"
    Write-Host "Convertidos:          $($script:Summary.Convertidos)"
    Write-Host "Ja eram Arte:         $($script:Summary.JaEramArte)"
    Write-Host "Duplicados:           $($script:Summary.Duplicados)"
    Write-Host "Desconhecidos:        $($script:Summary.Desconhecidos)"
    Write-Host "Ignorados:            $($script:Summary.Ignorados)"
    Write-Host "Erros:                $($script:Summary.Erros)"
    Write-Host "Tempo total:          $($Stopwatch.Elapsed.TotalSeconds.ToString('0.00')) segundos"
    Write-Host "====================================="
}

function Load-XmlDocument {
    <#
        Carrega um arquivo XML usando System.Xml.XmlDocument.

        Decisoes importantes:
        - PreserveWhitespace = true para preservar o maximo possivel da estrutura original.
        - Nao usa Replace.
        - Nao trata XML como texto.
        - Cada arquivo e carregado individualmente.
    #>

    param(
        [System.IO.FileInfo]$File
    )

    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.PreserveWhitespace = $true
        $xml.Load($File.FullName)

        return $xml
    }
    catch {
        throw "Erro ao carregar XML '$($File.Name)': $($_.Exception.Message)"
    }
}

function New-NFeNamespaceManager {
    <#
        Cria um XmlNamespaceManager com base no namespace real do XML.

        A NF-e normalmente usa:
        http://www.portalfiscal.inf.br/nfe

        Mesmo que o XML use namespace padrao sem prefixo, o XPath precisa
        de um prefixo artificial para consultar corretamente os nos.

        Importante:
        O XmlNamespaceManager pode ser tratado pelo PowerShell como objeto enumeravel.
        Por isso usamos "return ,$ns" para garantir que ele volte como um unico objeto,
        e nao como System.Object[].
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument
    )

    try {
        if ($null -eq $XmlDocument.DocumentElement) {
            throw "XML sem elemento raiz."
        }

        $namespaceUri = $XmlDocument.DocumentElement.NamespaceURI

        if ([string]::IsNullOrWhiteSpace($namespaceUri)) {
            throw "XML sem namespace. NF-e normalmente deve possuir namespace."
        }

        $ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList @($XmlDocument.NameTable)
        $ns.AddNamespace("nfe", $namespaceUri)

        return , $ns
    }
    catch {
        throw "Erro ao criar gerenciador de namespace: $($_.Exception.Message)"
    }
}

function Get-XmlNodeText {
    <#
        Retorna o texto de um no XML com seguranca.
        Caso o no seja nulo, retorna string vazia.
    #>

    param(
        [System.Xml.XmlNode]$Node
    )

    if ($null -eq $Node) {
        return ""
    }

    return $Node.InnerText.Trim()
}

function Get-NFeInfNode {
    <#
        Localiza o no infNFe de forma segura.

        Aceita XML nos formatos:
        - nfeProc/NFe/infNFe
        - NFe/infNFe

        Nao confia em posicao, linha ou ausencia de namespace.
        Utiliza XPath com namespace.
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    $paths = @(
        "/nfe:nfeProc/nfe:NFe/nfe:infNFe",
        "/nfe:NFe/nfe:infNFe"
    )

    foreach ($path in $paths) {
        $node = $XmlDocument.SelectSingleNode($path, $NamespaceManager)

        if ($null -ne $node) {
            return $node
        }
    }

    return $null
}

function Test-NFeDocument {
    <#
        Valida se o XML possui estrutura minima de NF-e.

        Regras:
        - Deve conter nfeProc ou NFe.
        - Deve conter infNFe.
        - Deve conter emit.
        - Deve conter dest.

        Esta validacao evita tentar alterar XML que nao seja NF-e.
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    $result = @{
        IsValid = $false
        Reason  = ""
        InfNFe  = $null
        Emit    = $null
        Dest    = $null
    }

    try {
        $rootName = $XmlDocument.DocumentElement.LocalName

        if (($rootName -ne "nfeProc") -and ($rootName -ne "NFe")) {
            $result.Reason = "Nao e uma NF-e valida. Raiz encontrada: $rootName"
            return $result
        }

        $infNFe = Get-NFeInfNode -XmlDocument $XmlDocument -NamespaceManager $NamespaceManager

        if ($null -eq $infNFe) {
            $result.Reason = "Nao e uma NF-e valida. No infNFe nao encontrado."
            return $result
        }

        $emit = $infNFe.SelectSingleNode("nfe:emit", $NamespaceManager)
        if ($null -eq $emit) {
            $result.Reason = "Nao e uma NF-e valida. No emit nao encontrado."
            return $result
        }

        $dest = $infNFe.SelectSingleNode("nfe:dest", $NamespaceManager)
        if ($null -eq $dest) {
            $result.Reason = "Nao e uma NF-e valida. No dest nao encontrado."
            return $result
        }

        $result.IsValid = $true
        $result.Reason = "NF-e valida."
        $result.InfNFe = $infNFe
        $result.Emit = $emit
        $result.Dest = $dest

        return $result
    }
    catch {
        $result.IsValid = $false
        $result.Reason = "Erro ao validar NF-e: $($_.Exception.Message)"
        return $result
    }
}

function Get-DestinationInfo {
    <#
        Extrai informacoes principais do destinatario.

        A validacao principal sera feita por CNPJ, pois o nome pode variar.
    #>

    param(
        [System.Xml.XmlNode]$DestNode,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    $cnpjNode = $DestNode.SelectSingleNode("nfe:CNPJ", $NamespaceManager)
    $nomeNode = $DestNode.SelectSingleNode("nfe:xNome", $NamespaceManager)

    $cnpj = Get-XmlNodeText -Node $cnpjNode
    $nome = Get-XmlNodeText -Node $nomeNode

    $cnpj = $cnpj -replace "\D", ""

    return @{
        CNPJ = $cnpj
        Nome = $nome
    }
}

function Get-ConfiguredCompanyName {
    <#
        Busca o nome da empresa dentro do config.json pelo CNPJ.

        O config.json possui EmpresasValidas como objeto:
        "58345863000180": "MANIA..."
    #>

    param(
        [string]$CNPJ
    )

    if ([string]::IsNullOrWhiteSpace($CNPJ)) {
        return ""
    }

    $property = $script:Config.EmpresasValidas.PSObject.Properties[$CNPJ]

    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function Test-IsDestinationArte {
    <#
        Verifica se o destinatario atual ja e a empresa destino.

        Nesta ferramenta, a empresa destino vem do config.json.
        Atualmente: ARTE DA SEDUCAO DE SOROCABA LTDA.
    #>

    param(
        [string]$CNPJ
    )

    $destinationCnpj = [string]$script:Config.EmpresaDestino.CNPJ
    $destinationCnpj = $destinationCnpj -replace "\D", ""

    return ($CNPJ -eq $destinationCnpj)
}

function Get-XmlClassification {
    <#
        Classifica um XML de NF-e sem alterar o documento.

        Resultados possiveis:
        - Ja era Arte
        - Valido para converter
        - Destinatario desconhecido
        - Ignorado
        - Erro
    #>

    param(
        [System.IO.FileInfo]$File
    )

    $classification = @{
        Resultado = ""
        Empresa   = ""
        Mensagem  = ""
    }

    try {
        $xml = Load-XmlDocument -File $File
        $ns = New-NFeNamespaceManager -XmlDocument $xml

        $validation = Test-NFeDocument -XmlDocument $xml -NamespaceManager $ns

        if (-not $validation.IsValid) {
            $classification.Resultado = "Ignorado"
            $classification.Empresa = ""
            $classification.Mensagem = $validation.Reason
            return $classification
        }

        $destInfo = Get-DestinationInfo -DestNode $validation.Dest -NamespaceManager $ns

        if ([string]::IsNullOrWhiteSpace($destInfo.CNPJ)) {
            $classification.Resultado = "Desconhecido"
            $classification.Empresa = ""
            $classification.Mensagem = "Destinatario sem CNPJ."
            return $classification
        }

        $configuredCompanyName = Get-ConfiguredCompanyName -CNPJ $destInfo.CNPJ

        if ([string]::IsNullOrWhiteSpace($configuredCompanyName)) {
            $classification.Resultado = "Desconhecido"
            $classification.Empresa = $destInfo.Nome
            $classification.Mensagem = "CNPJ do destinatario nao esta na lista de empresas validas: $($destInfo.CNPJ)"
            return $classification
        }

        if (Test-IsDestinationArte -CNPJ $destInfo.CNPJ) {
            $classification.Resultado = "Ja era Arte"
            $classification.Empresa = $configuredCompanyName
            $classification.Mensagem = "XML ja possui destinatario igual a empresa destino."
            return $classification
        }

        $classification.Resultado = "Valido para converter"
        $classification.Empresa = $configuredCompanyName
        $classification.Mensagem = "XML valido. Destinatario sera convertido futuramente para Arte."

        return $classification
    }
    catch {
        $classification.Resultado = "Erro"
        $classification.Empresa = ""
        $classification.Mensagem = $_.Exception.Message
        return $classification
    }
}

function Get-UniqueFilePath {
    <#
        Retorna um caminho unico para salvar arquivo sem sobrescrever.

        Exemplo:
        nota.xml
        nota (1).xml
        nota (2).xml
    #>

    param(
        [string]$Directory,
        [string]$FileName
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)

    $candidate = Join-Path $Directory $FileName
    $counter = 1

    while (Test-Path -LiteralPath $candidate) {
        $newName = "{0} ({1}){2}" -f $baseName, $counter, $extension
        $candidate = Join-Path $Directory $newName
        $counter++
    }

    return $candidate
}

function New-DestinationNode {
    <#
        Cria um novo no <dest> com base no config.json.

        Importante:
        - Os dados da empresa nao ficam fixos no codigo.
        - O namespace usado e o mesmo namespace da NF-e original.
        - A ordem dos elementos segue o XML real da Arte:
          CNPJ, xNome, enderDest, indIEDest, IE, email.
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument,
        [string]$NamespaceUri
    )

    $destConfig = $script:Config.EmpresaDestino

    $dest = $XmlDocument.CreateElement("dest", $NamespaceUri)

    $cnpj = $XmlDocument.CreateElement("CNPJ", $NamespaceUri)
    $cnpj.InnerText = [string]$destConfig.CNPJ
    [void]$dest.AppendChild($cnpj)

    $xNome = $XmlDocument.CreateElement("xNome", $NamespaceUri)
    $xNome.InnerText = [string]$destConfig.xNome
    [void]$dest.AppendChild($xNome)

    $enderDest = $XmlDocument.CreateElement("enderDest", $NamespaceUri)

    $addressFields = @(
        "xLgr",
        "nro",
        "xCpl",
        "xBairro",
        "cMun",
        "xMun",
        "UF",
        "CEP",
        "cPais",
        "xPais",
        "fone"
    )

    foreach ($field in $addressFields) {
        $value = $destConfig.enderDest.$field

        if ($null -ne $value) {
            $node = $XmlDocument.CreateElement($field, $NamespaceUri)
            $node.InnerText = [string]$value
            [void]$enderDest.AppendChild($node)
        }
    }

    [void]$dest.AppendChild($enderDest)

    $indIEDest = $XmlDocument.CreateElement("indIEDest", $NamespaceUri)
    $indIEDest.InnerText = [string]$destConfig.indIEDest
    [void]$dest.AppendChild($indIEDest)

    $ie = $XmlDocument.CreateElement("IE", $NamespaceUri)
    $ie.InnerText = [string]$destConfig.IE
    [void]$dest.AppendChild($ie)

    $email = $XmlDocument.CreateElement("email", $NamespaceUri)
    $email.InnerText = [string]$destConfig.email
    [void]$dest.AppendChild($email)

    return $dest
}

function Replace-DestinationNode {
    <#
        Substitui exclusivamente o bloco <dest>.

        Nao altera:
        - emit
        - Signature
        - protNFe
        - produtos
        - impostos
        - total
        - nenhum outro no
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument,
        [System.Xml.XmlNode]$OldDestNode
    )

    try {
        $namespaceUri = $XmlDocument.DocumentElement.NamespaceURI
        $newDestNode = New-DestinationNode -XmlDocument $XmlDocument -NamespaceUri $namespaceUri

        [void]$OldDestNode.ParentNode.ReplaceChild($newDestNode, $OldDestNode)

        return $XmlDocument
    }
    catch {
        throw "Erro ao substituir no dest: $($_.Exception.Message)"
    }
}

function Save-XmlDocumentControlled {
    <#
        Salva o XML usando XmlWriterSettings.

        Nao usa XmlDocument.Save() diretamente.

        Decisoes:
        - UTF-8 sem BOM.
        - Declaracao XML preservada/emitida.
        - Indentacao desativada para respeitar PreserveWhitespace.
        - NewLineHandling None para nao normalizar quebras de linha.
    #>

    param(
        [System.Xml.XmlDocument]$XmlDocument,
        [string]$OutputPath
    )

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Encoding = $utf8NoBom
        $settings.Indent = $false
        $settings.OmitXmlDeclaration = $false
        $settings.NewLineHandling = [System.Xml.NewLineHandling]::None

        $writer = $null

        try {
            $writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
            $XmlDocument.WriteTo($writer)
        }
        finally {
            if ($null -ne $writer) {
                $writer.Close()
                $writer.Dispose()
            }
        }
    }
    catch {
        throw "Erro ao salvar XML em '$OutputPath': $($_.Exception.Message)"
    }
}
function Copy-OriginalToConverted {
    <#
        Copia XML original para Convertidos quando ele ja e Arte.

        Usa nome descritivo quando informado.
        Usa caminho unico para nunca sobrescrever.
    #>

    param(
        [System.IO.FileInfo]$File,
        [string]$OutputFileName
    )

    if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
        $OutputFileName = $File.Name
    }

    $destinationPath = Get-UniqueFilePath -Directory $script:Paths.Convertidos -FileName $OutputFileName
    Copy-Item -LiteralPath $File.FullName -Destination $destinationPath -Force:$false

    return $destinationPath
}

function Move-OriginalToProcessed {
    <#
        Move o XML original da pasta Entrada para Processados.

        Usa nome descritivo quando informado.
        Usa caminho unico para nunca sobrescrever um original ja processado.
    #>

    param(
        [System.IO.FileInfo]$File,
        [string]$OutputFileName
    )

    if ([string]::IsNullOrWhiteSpace($OutputFileName)) {
        $OutputFileName = $File.Name
    }

    $processedPath = Get-UniqueFilePath -Directory $script:Paths.Processados -FileName $OutputFileName
    Move-Item -LiteralPath $File.FullName -Destination $processedPath -Force:$false

    return $processedPath
}

function ConvertTo-SafeFileNamePart {
    <#
        Converte um texto em parte segura para nome de arquivo.

        Remove:
        - caracteres invalidos do Windows
        - acentos comuns
        - espacos duplicados

        Troca espacos por underline para facilitar leitura.
    #>

    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "SEM_INFO"
    }

    $value = $Text.Trim().ToUpperInvariant()

    $value = $value `
        -replace "[ÁÀÂÃÄ]", "A" `
        -replace "[ÉÈÊË]", "E" `
        -replace "[ÍÌÎÏ]", "I" `
        -replace "[ÓÒÔÕÖ]", "O" `
        -replace "[ÚÙÛÜ]", "U" `
        -replace "Ç", "C"

    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $escaped = [Regex]::Escape([string]$char)
        $value = $value -replace $escaped, ""
    }

    $value = $value -replace "[^A-Z0-9 ]", " "
    $value = $value -replace "\s+", " "
    $value = $value.Trim()
    $value = $value -replace " ", "_"

    if ([string]::IsNullOrWhiteSpace($value)) {
        return "SEM_INFO"
    }

    return $value
}

function Get-NFeMetadata {
    <#
        Extrai dados usados para montar o nome do arquivo.

        Campos:
        - Numero da NF: ide/nNF
        - Data de emissao: ide/dhEmi ou ide/dEmi
        - Emitente/marca: emit/xNome
        - Destinatario original/loja: dest/xNome

        Tudo via XPath com namespace.
    #>

    param(
        [System.Xml.XmlNode]$InfNFeNode,
        [System.Xml.XmlNamespaceManager]$NamespaceManager
    )

    $nNFNode = $InfNFeNode.SelectSingleNode("nfe:ide/nfe:nNF", $NamespaceManager)
    $dhEmiNode = $InfNFeNode.SelectSingleNode("nfe:ide/nfe:dhEmi", $NamespaceManager)

    if ($null -eq $dhEmiNode) {
        $dhEmiNode = $InfNFeNode.SelectSingleNode("nfe:ide/nfe:dEmi", $NamespaceManager)
    }

    $emitNomeNode = $InfNFeNode.SelectSingleNode("nfe:emit/nfe:xNome", $NamespaceManager)
    $destNomeNode = $InfNFeNode.SelectSingleNode("nfe:dest/nfe:xNome", $NamespaceManager)

    $numeroNF = Get-XmlNodeText -Node $nNFNode
    $dataEmissao = Get-XmlNodeText -Node $dhEmiNode
    $emitente = Get-XmlNodeText -Node $emitNomeNode
    $destinatarioOriginal = Get-XmlNodeText -Node $destNomeNode

    $mesEmissao = "SEM_MES"

    if (-not [string]::IsNullOrWhiteSpace($dataEmissao)) {
        try {
            # NF-e normalmente vem como 2026-06-24T09:17:36-03:00.
            # Para o nome do arquivo, precisamos apenas de AAAA-MM.
            if ($dataEmissao.Length -ge 7) {
                $mesEmissao = $dataEmissao.Substring(0, 7)
            }
        }
        catch {
            $mesEmissao = "SEM_MES"
        }
    }

    if ([string]::IsNullOrWhiteSpace($numeroNF)) {
        $numeroNF = "SEM_NUMERO"
    }

    return @{
        NumeroNF             = $numeroNF
        MesEmissao           = $mesEmissao
        Emitente             = $emitente
        DestinatarioOriginal = $destinatarioOriginal
    }
}

function Get-FirstWords {
    <#
        Retorna as primeiras palavras de um texto.

        Uso:
        - Loja original: 1 palavra
        - Emitente/marca: 2 palavras

        Usa @() para garantir que o resultado sempre seja tratado como lista,
        mesmo quando existir apenas uma palavra.
    #>

    param(
        [AllowNull()]
        [string]$Text,

        [int]$Count = 1
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "SEM_INFO"
    }

    $cleanText = $Text.Trim()
    $words = @($cleanText -split "\s+")

    if ($words.Count -eq 0) {
        return "SEM_INFO"
    }

    if ($words.Count -lt $Count) {
        $Count = $words.Count
    }

    return ($words[0..($Count - 1)] -join " ")
}

function New-NFeOutputFileName {
    <#
        Monta o nome final do arquivo convertido/processado.

        Padrao novo:
        NF_<numero>_<loja inicial>_<duas primeiras palavras do emitente>_<ano-mes>.xml

        Exemplo:
        NF_7645_ARTE_LINDA_BRASIL_2026_06.xml
        NF_1234_CALCINHA_NOME_MARCA_2026_07.xml
    #>

    param(
        [hashtable]$Metadata
    )

    $numero = ConvertTo-SafeFileNamePart -Text $Metadata.NumeroNF

    # Loja original: apenas primeira palavra da razao social do destinatario original.
    $lojaOriginalCurta = Get-FirstWords -Text $Metadata.DestinatarioOriginal -Count 1
    $lojaOriginal = ConvertTo-SafeFileNamePart -Text $lojaOriginalCurta

    # Emitente/marca: apenas as duas primeiras palavras da razao social do emitente.
    $emitenteCurto = Get-FirstWords -Text $Metadata.Emitente -Count 2
    $emitente = ConvertTo-SafeFileNamePart -Text $emitenteCurto

    $mes = ConvertTo-SafeFileNamePart -Text $Metadata.MesEmissao

    return "NF_{0}_{1}_{2}_{3}.xml" -f $numero, $lojaOriginal, $emitente, $mes
}

function Convert-NFeDestination {
    <#
        Converte o XML para a empresa destino.

        Fluxo:
        - carrega XML
        - valida NF-e
        - extrai metadados para nome do arquivo
        - substitui somente <dest>
        - salva em XML\Convertidos com nome descritivo
        - move original para XML\Processados com o mesmo nome descritivo
    #>

    param(
        [System.IO.FileInfo]$File
    )

    $xml = Load-XmlDocument -File $File
    $ns = New-NFeNamespaceManager -XmlDocument $xml
    $validation = Test-NFeDocument -XmlDocument $xml -NamespaceManager $ns

    if (-not $validation.IsValid) {
        throw $validation.Reason
    }

    $metadata = Get-NFeMetadata -InfNFeNode $validation.InfNFe -NamespaceManager $ns
    $outputFileName = New-NFeOutputFileName -Metadata $metadata

    $destInfo = Get-DestinationInfo -DestNode $validation.Dest -NamespaceManager $ns

    if ([string]::IsNullOrWhiteSpace($destInfo.CNPJ)) {
        throw "Destinatario sem CNPJ."
    }

    $configuredCompanyName = Get-ConfiguredCompanyName -CNPJ $destInfo.CNPJ

    if ([string]::IsNullOrWhiteSpace($configuredCompanyName)) {
        throw "CNPJ do destinatario nao esta na lista de empresas validas: $($destInfo.CNPJ)"
    }

    $convertedPath = Get-UniqueFilePath -Directory $script:Paths.Convertidos -FileName $outputFileName

    $xml = Replace-DestinationNode -XmlDocument $xml -OldDestNode $validation.Dest
    Save-XmlDocumentControlled -XmlDocument $xml -OutputPath $convertedPath

    $processedPath = Move-OriginalToProcessed -File $File -OutputFileName $outputFileName

    return @{
        ConvertedPath   = $convertedPath
        ProcessedPath   = $processedPath
        OriginalCompany = $configuredCompanyName
        OutputFileName  = $outputFileName
    }
}

function Process-FilePlaceholder {
    <#
        Parte 3:
        Processa o XML de verdade.

        Regras:
        - Se ja existir em Convertidos, ignora como duplicado.
        - Se nao for NF-e, ignora.
        - Se destinatario for desconhecido, nao altera e nao move.
        - Se ja for Arte, copia para Convertidos e move original para Processados.
        - Se for empresa valida diferente de Arte, substitui <dest>, salva em Convertidos e move original para Processados.
        - Em DryRun, apenas simula. Nao grava e nao move nada.
    #>

    param(
        [System.IO.FileInfo]$File
    )

    $fileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (Test-ConvertedExists -File $File) {
            $script:Summary.Duplicados++

            Write-Log `
                -Arquivo $File.Name `
                -Resultado "Ja convertido" `
                -Empresa "" `
                -TempoMs $fileStopwatch.ElapsedMilliseconds `
                -Mensagem "Arquivo ja existe na pasta XML\Convertidos."

            return
        }

        $classification = Get-XmlClassification -File $File

        switch ($classification.Resultado) {
            "Ja era Arte" {
                if ($DryRun) {
                    $script:Summary.JaEramArte++

                    Write-Log `
                        -Arquivo $File.Name `
                        -Resultado "Ja era Arte" `
                        -Empresa $classification.Empresa `
                        -TempoMs $fileStopwatch.ElapsedMilliseconds `
                        -Mensagem "DryRun: copiaria para Convertidos e moveria original para Processados."

                    return
                }

                $xml = Load-XmlDocument -File $File
                $ns = New-NFeNamespaceManager -XmlDocument $xml
                $validation = Test-NFeDocument -XmlDocument $xml -NamespaceManager $ns

                if (-not $validation.IsValid) {
                    throw $validation.Reason
                }

                $metadata = Get-NFeMetadata -InfNFeNode $validation.InfNFe -NamespaceManager $ns
                $outputFileName = New-NFeOutputFileName -Metadata $metadata

                $convertedPath = Copy-OriginalToConverted -File $File -OutputFileName $outputFileName
                $processedPath = Move-OriginalToProcessed -File $File -OutputFileName $outputFileName

                $script:Summary.JaEramArte++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Ja era Arte" `
                    -Empresa $classification.Empresa `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem "Copiado para Convertidos: $convertedPath | Original movido para Processados: $processedPath"

                return
            }

            "Valido para converter" {
                if ($DryRun) {
                    $script:Summary.Convertidos++

                    Write-Log `
                        -Arquivo $File.Name `
                        -Resultado "Valido para converter" `
                        -Empresa $classification.Empresa `
                        -TempoMs $fileStopwatch.ElapsedMilliseconds `
                        -Mensagem "DryRun: substituiria dest por Arte, salvaria em Convertidos e moveria original para Processados."

                    return
                }

                $result = Convert-NFeDestination -File $File

                $script:Summary.Convertidos++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Convertido" `
                    -Empresa $result.OriginalCompany `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem "Convertido em: $($result.ConvertedPath) | Original movido para: $($result.ProcessedPath)"

                return
            }

            "Desconhecido" {
                $script:Summary.Desconhecidos++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Desconhecido" `
                    -Empresa $classification.Empresa `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem $classification.Mensagem

                return
            }

            "Ignorado" {
                $script:Summary.Ignorados++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Ignorado" `
                    -Empresa $classification.Empresa `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem $classification.Mensagem

                return
            }

            "Erro" {
                $script:Summary.Erros++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Erro" `
                    -Empresa $classification.Empresa `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem $classification.Mensagem

                return
            }

            default {
                $script:Summary.Ignorados++

                Write-Log `
                    -Arquivo $File.Name `
                    -Resultado "Ignorado" `
                    -Empresa $classification.Empresa `
                    -TempoMs $fileStopwatch.ElapsedMilliseconds `
                    -Mensagem "Classificacao nao reconhecida: $($classification.Resultado)"

                return
            }
        }
    }
    catch {
        $script:Summary.Erros++

        Write-Log `
            -Arquivo $File.Name `
            -Resultado "Erro" `
            -Empresa "" `
            -TempoMs $fileStopwatch.ElapsedMilliseconds `
            -Mensagem $_.Exception.Message
    }
    finally {
        $fileStopwatch.Stop()
    }
}

function Main {
    <#
        Ponto principal da aplicacao.

        Nesta Parte 1:
        - inicializa estrutura
        - carrega configuracao
        - cria log
        - lista XML
        - verifica duplicados
        - mostra progresso
        - exibe resumo final
    #>

    $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Show-Header

        Initialize-Paths
        Initialize-Folders

        $script:Config = Load-Configuration

        Initialize-LogFile

        $files = @(Get-XmlFiles)
        $script:Summary.ArquivosEncontrados = $files.Count

        if ($files.Count -eq 0) {
            Write-Host "Nenhum arquivo XML encontrado na pasta XML\Entrada."

            Write-Log `
                -Arquivo "" `
                -Resultado "Sem arquivos" `
                -Empresa "" `
                -TempoMs 0 `
                -Mensagem "Nenhum XML encontrado para processamento em XML\Entrada."

            return
        }

        for ($i = 0; $i -lt $files.Count; $i++) {
            $file = $files[$i]

            $percent = [int](($i + 1) / $files.Count * 100)

            Write-Progress `
                -Activity "Processando XML" `
                -Status "$($i + 1) de $($files.Count): $($file.Name)" `
                -PercentComplete $percent

            Process-FilePlaceholder -File $file
        }

        Write-Progress -Activity "Processando XML" -Completed
    }
    catch {
        $script:Summary.Erros++

        Write-Host ""
        Write-Host "Erro geral: $($_.Exception.Message)" -ForegroundColor Red

        try {
            Write-Log `
                -Arquivo "" `
                -Resultado "Erro geral" `
                -Empresa "" `
                -TempoMs 0 `
                -Mensagem $_.Exception.Message
        }
        catch {}
    }
    finally {
        $totalStopwatch.Stop()
        Show-Summary -Stopwatch $totalStopwatch

        Write-Host ""
        Write-Host "Pressione ENTER para sair..."
        [void][System.Console]::ReadLine()
    }
}

Main
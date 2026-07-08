# NFe DestSync

Version 1.0.0

**NFe DestSync** is a Windows automation tool for preparing Brazilian NF-e XML files before importing them into an ERP system.

The tool reads NF-e XML files from an input folder, validates the original recipient company, and safely replaces only the NF-e `<dest>` recipient block with the destination company data configured locally.

It was created to reduce manual XML editing, avoid import errors, and standardize NF-e files before internal processing.

---

## Important Privacy Notice

This repository is intended to be safe for public sharing.

Do not commit private or real company data, such as:

* Real NF-e XML files
* Real CNPJ numbers
* Real state registration numbers
* Real company names, if sensitive
* Real addresses
* Real phone numbers
* Real company emails
* Real CSV logs
* Local `config.json` files
* Compiled `.exe` files should not be committed directly to the repository. If needed, publish them as release assets in the GitHub Releases section.

The repository should include only:

```text
config.example.json
```

Your real configuration file should be named:

```text
config.json
```

and must stay only on your local computer.

---

## Purpose

NFe DestSync was created to automate the process of adapting NF-e XML files for ERP import workflows.

The tool:

* Reads XML files from `XML/Entrada`
* Validates whether each file is a Brazilian NF-e XML
* Checks if the original recipient CNPJ is listed as an allowed company
* Replaces only the `<dest>` block with the configured destination company
* Preserves all other NF-e sections
* Saves converted files into `XML/Convertidos`
* Moves original files into `XML/Processados`
* Generates daily CSV logs in `Logs`
* Supports a safe test mode using `-DryRun`

---

## What Is Modified

Only the NF-e recipient block is modified:

```xml
<dest>
  ...
</dest>
```

The following sections are not modified:

* `<emit>`
* `<Signature>`
* `<protNFe>`
* Products
* Taxes
* Totals
* Transport data
* Payment data
* Additional information
* Any other XML section outside `<dest>`

The XML is modified using XML DOM/XPath handling, not simple text replacement.

---

## Folder Structure

The application must be executed from its root folder.

Expected structure:

```text
NFeDestSync/
│
├── NFeDestSync.ps1
├── config.example.json
├── README.md
├── .gitignore
│
├── XML/
│   ├── Entrada/
│   │   └── .gitkeep
│   ├── Convertidos/
│   │   └── .gitkeep
│   ├── Processados/
│   │   └── .gitkeep
│   └── Backup/
│       └── .gitkeep
│
└── Logs/
    └── .gitkeep
```

---

## Folder Usage

### `XML/Entrada`

Place the original NF-e XML files here before running the program.

### `XML/Convertidos`

Converted XML files are saved here.

These are the files that should be imported into the ERP system.

### `XML/Processados`

Original XML files are moved here after successful processing.

### `XML/Backup`

Optional backup folder.

Depending on the configuration, this folder may be used to store additional backup copies.

### `Logs`

Daily CSV logs are saved here.

---

## Configuration

The repository includes a public example configuration file:

```text
config.example.json
```

To use the tool locally:

1. Copy `config.example.json`
2. Rename the copy to `config.json`
3. Fill in your real company data
4. Keep `config.json` private

Do not commit `config.json` to GitHub.

---

## Configuration Overview

The configuration file contains:

* Application version
* Destination alias
* Backup setting
* Overwrite setting
* CSV log setting
* Allowed original recipient companies
* Destination company data

Example structure:

```json
{
  "Versao": 1,
  "Destino": "DESTINATION_ALIAS",
  "CriarBackup": false,
  "SobrescreverConvertidos": false,
  "GerarLogCsv": true,
  "EmpresasValidas": {
    "00000000000000": "SOURCE COMPANY ONE LTDA",
    "11111111111111": "SOURCE COMPANY TWO LTDA"
  },
  "EmpresaDestino": {
    "CNPJ": "11111111111111",
    "xNome": "DESTINATION COMPANY LTDA",
    "enderDest": {
      "xLgr": "STREET NAME",
      "nro": "123",
      "xCpl": "COMPLEMENT",
      "xBairro": "DISTRICT",
      "cMun": "0000000",
      "xMun": "CITY",
      "UF": "SP",
      "CEP": "00000000",
      "cPais": "1058",
      "xPais": "Brasil",
      "fone": "0000000000"
    },
    "indIEDest": "1",
    "IE": "000000000000",
    "email": "email@example.com"
  }
}
```

---

## `EmpresasValidas`

The `EmpresasValidas` section defines which original recipient companies are allowed to be converted.

Example:

```json
"EmpresasValidas": {
  "00000000000000": "SOURCE COMPANY ONE LTDA",
  "11111111111111": "SOURCE COMPANY TWO LTDA"
}
```

Rules:

* Use only numbers in the CNPJ
* Do not use dots, slashes or hyphens
* If the original recipient CNPJ is not listed, the XML will not be converted
* Unknown recipients are logged and left in the input folder

---

## `EmpresaDestino`

The `EmpresaDestino` section defines the company data that will replace the original NF-e `<dest>` block.

Example:

```json
"EmpresaDestino": {
  "CNPJ": "11111111111111",
  "xNome": "DESTINATION COMPANY LTDA",
  "enderDest": {
    "xLgr": "STREET NAME",
    "nro": "123",
    "xCpl": "COMPLEMENT",
    "xBairro": "DISTRICT",
    "cMun": "0000000",
    "xMun": "CITY",
    "UF": "SP",
    "CEP": "00000000",
    "cPais": "1058",
    "xPais": "Brasil",
    "fone": "0000000000"
  },
  "indIEDest": "1",
  "IE": "000000000000",
  "email": "email@example.com"
}
```

After changing `config.json`, recompilation is not required.

---

## How to Use

### Step 1

Place the original NF-e XML files into:

```text
XML/Entrada
```

### Step 2

Run the executable or PowerShell script.

Executable:

```powershell
.\NFeDestSync.exe
```

PowerShell script:

```powershell
.\NFeDestSync.ps1
```

### Step 3

After processing:

* Converted files will be available in `XML/Convertidos`
* Original files will be moved to `XML/Processados`
* Logs will be saved in `Logs`
* Files with unknown recipients will remain in `XML/Entrada`

---

## Dry Run Mode

Before running the actual conversion, use Dry Run mode:

```powershell
.\NFeDestSync.exe -DryRun
```

or:

```powershell
.\NFeDestSync.ps1 -DryRun
```

In Dry Run mode, the program:

* Reads XML files
* Validates the NF-e structure
* Identifies the original recipient
* Shows what would be converted
* Writes logs

But it does not:

* Save converted XML files
* Move original files
* Modify any file

Dry Run mode is recommended before processing large batches.

---

## Normal Execution

To process files for real, run:

```powershell
.\NFeDestSync.exe
```

or:

```powershell
.\NFeDestSync.ps1
```

The program will:

1. Read XML files from `XML/Entrada`
2. Validate whether each file is a valid NF-e
3. Check the recipient CNPJ
4. Convert accepted companies to the configured destination company
5. Save converted files in `XML/Convertidos`
6. Move original files to `XML/Processados`
7. Register all results in `Logs`

---

## File Renaming Rule

Converted and processed files are automatically renamed using NF-e metadata.

Format:

```text
NF_<invoice_number>_<original_recipient_first_word>_<issuer_first_two_words>_<year_month>.xml
```

Example:

```text
NF_12345_SOURCE_SUPPLIER_NAME_2026_07.xml
```

The name is generated from:

* Invoice number: `ide/nNF`
* Original recipient/store: `dest/xNome`, first word only
* Issuer/brand: `emit/xNome`, first two words only
* Issue month: `ide/dhEmi` or `ide/dEmi`

If a file with the same name already exists, the program creates a unique name automatically:

```text
NF_12345_SOURCE_SUPPLIER_NAME_2026_07.xml
NF_12345_SOURCE_SUPPLIER_NAME_2026_07 (1).xml
NF_12345_SOURCE_SUPPLIER_NAME_2026_07 (2).xml
```

No file is overwritten.

---

## Logs

Logs are saved daily in CSV format:

```text
Logs/YYYY-MM-DD.csv
```

Example:

```text
Logs/2026-07-08.csv
```

Log columns:

```text
Data
Hora
Arquivo
Resultado
Empresa
TempoMs
Mensagem
```

Possible results:

### `Convertido`

The XML was converted successfully.

### `Ja era destino`

The XML already had the configured destination company as recipient.

### `Ja convertido`

A file with the same name already exists in the converted folder.

### `Desconhecido`

The recipient CNPJ is not listed in `EmpresasValidas`.

### `Ignorado`

The file is not a valid NF-e or does not contain the required structure.

### `Erro`

An error occurred while processing the file.

---

## Technical Details

NFe DestSync was built for:

* Windows 10
* Windows 11
* PowerShell 5.1
* ps2exe / Invoke-ps2exe

The XML is manipulated using:

* `System.Xml.XmlDocument`
* `XmlNamespaceManager`
* XPath

The tool does not use string replacement to modify XML content.

Only the `<dest>` block is replaced.

---

## XML Signature Warning

Any modification to an NF-e XML file invalidates its original digital signature.

This tool is intended only for internal operational use before importing XML files into an ERP system.

Converted XML files should not be treated as legally valid signed fiscal documents.

Always keep the original XML files.

---

## How to Recompile the EXE

The source code is:

```text
NFeDestSync.ps1
```

To generate the executable again, open PowerShell in the root folder and run:

```powershell
Invoke-ps2exe `
  -inputFile .\NFeDestSync.ps1 `
  -outputFile .\NFeDestSync.exe `
  -noConsole:$false `
  -title "NFe DestSync" `
  -description "NF-e XML destination block synchronization tool" `
  -company "Your Company" `
  -product "NFe DestSync" `
  -version "1.0.0"
```

If the executable is open, close it before recompiling.

If needed, remove the old executable first:

```powershell
Remove-Item .\NFeDestSync.exe -Force
```

Then run the `Invoke-ps2exe` command again.

---

## Recommended Workflow

1. Download or export NF-e XML files from your source system.
2. Copy them into `XML/Entrada`.
3. Run:

```powershell
.\NFeDestSync.exe -DryRun
```

4. Check the summary and logs.
5. If everything looks correct, run:

```powershell
.\NFeDestSync.exe
```

6. Import the files from `XML/Convertidos` into your ERP system.
7. Keep `XML/Processados` as the original file history.
8. Check `Logs` if any file was ignored, unknown or failed.

---

## Important Notes

Do not manually edit converted XML files.

Do not place converted XML files back into `XML/Entrada`.

Do not commit real XML files to GitHub.

Do not commit real logs to GitHub.

Do not commit your private `config.json` file.

Do not rename the required folders unless the PowerShell code is updated accordingly.

Required folders:

```text
XML/Entrada
XML/Convertidos
XML/Processados
XML/Backup
Logs
```

---

## Version History

### Version 1.0.0

* Reads XML files from `XML/Entrada`
* Validates NF-e structure
* Handles NF-e namespace correctly
* Validates recipient by CNPJ
* Converts accepted companies to the configured destination company
* Copies files that already use the configured destination company
* Saves converted files in `XML/Convertidos`
* Moves originals to `XML/Processados`
* Generates CSV logs
* Supports Dry Run mode
* Automatically renames files using invoice metadata
* Compatible with PowerShell 5.1 and ps2exe

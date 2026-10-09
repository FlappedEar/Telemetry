; NSIS installer for FlappedEar Telemetry (Windows 10/11, 64-bit).
;
; The install folder is fixed: %LOCALAPPDATA%\Programs\FlappedEar Telemetry.
; There is no folder page, and the NSIS /D= argument is ignored (.onInit puts
; the fixed folder back), so a command line cannot point the installer at a
; folder of the user's. Directory-wide deletion happens only in a folder that
; carries the install marker below (or a 0.3.0 install, which has none yet),
; and the uninstaller refuses to run anywhere but in the fixed folder.
; An update is staged in "<folder>.new" and swapped in, so a failed copy
; leaves the old version in place; it stops while the app is running.
;
; Built by the Release workflow:
;   makensis -DVERSION=0.3.0 -DSOURCE_DIR=<Release folder> -DOUTFILE=<setup.exe> installer.nsi
; It installs for the current user only (no administrator rights), adds a
; Start menu shortcut and an uninstaller. Saved days live in the user's app
; data, not in the install folder, so uninstalling never touches them.
; The installer is not code-signed, so SmartScreen warns on first start.

Unicode true
!include "MUI2.nsh"
!include "x64.nsh"

!ifndef VERSION
  !error "Pass /DVERSION=x.y.z"
!endif
!ifndef SOURCE_DIR
  !error "Pass /DSOURCE_DIR=<folder with telemetry.exe>"
!endif
!ifndef OUTFILE
  !define OUTFILE "FlappedEar-Telemetry-${VERSION}-windows-setup.exe"
!endif

!define APP_NAME "FlappedEar Telemetry"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\FlappedEarTelemetry"

!define INSTALL_DIR "$LOCALAPPDATA\Programs\${APP_NAME}"
; Written into every folder this installer creates; the only proof of
; ownership that allows deleting the folder as a whole.
!define MARKER ".flappedear-telemetry-install"

Name "${APP_NAME}"
OutFile "${OUTFILE}"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Apache License 2.0"

!define MUI_ICON "..\runner\resources\app_icon.ico"
!define MUI_UNICON "..\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\telemetry.exe"

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Polish"

; Stops (exit code 2) while the app runs: a running exe cannot be opened for
; writing. Silent runs cancel at once; interactive runs may close the app
; and retry.
!macro CheckAppClosed
  ${Do}
    ${IfNot} ${FileExists} "$INSTDIR\telemetry.exe"
      ${Break}
    ${EndIf}
    ClearErrors
    FileOpen $0 "$INSTDIR\telemetry.exe" a
    ${IfNot} ${Errors}
      FileClose $0
      ${Break}
    ${EndIf}
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${APP_NAME} is running. Close it, then choose Retry." /SD IDCANCEL IDRETRY +3
    SetErrorLevel 2
    Abort
  ${Loop}
!macroend

; Deletes the folder on the stack when it carries the install marker.
Function ClearOwnedDir
  Exch $0
  ${If} ${FileExists} "$0\${MARKER}"
    RMDir /r "$0"
  ${EndIf}
  Pop $0
FunctionEnd

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} needs 64-bit Windows." /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}
  StrLen $0 "$LOCALAPPDATA"
  ${If} $0 < 4
    MessageBox MB_OK|MB_ICONSTOP "The per-user program folder of this Windows account was not found." /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}
  ; /D= (or anything else) may have chosen another folder: ignore it.
  StrCpy $0 "${INSTALL_DIR}"
  ${If} "$INSTDIR" != "$0"
    ${IfNot} ${Silent}
      MessageBox MB_OK|MB_ICONINFORMATION "${APP_NAME} always installs into $0. The folder you chose is ignored."
    ${EndIf}
    StrCpy $INSTDIR "$0"
  ${EndIf}
FunctionEnd

Section "Install"
  ; Is there an install of ours here? 0.3.0 wrote no marker, but had both files.
  StrCpy $R2 0
  ${If} ${FileExists} "$INSTDIR\${MARKER}"
    StrCpy $R2 1
  ${ElseIf} ${FileExists} "$INSTDIR\telemetry.exe"
  ${AndIf} ${FileExists} "$INSTDIR\Uninstall.exe"
    StrCpy $R2 1
  ${EndIf}
  ; Any other folder with content is not ours to delete or write into.
  ${If} $R2 == 0
  ${AndIf} ${FileExists} "$INSTDIR\*.*"
    RMDir "$INSTDIR" ; succeeds only when the folder is empty
    ${If} ${FileExists} "$INSTDIR\*.*"
      MessageBox MB_OK|MB_ICONSTOP "$INSTDIR already exists and was not created by this installer. Nothing was changed. Move or rename that folder, then install again." /SD IDOK
      Abort
    ${EndIf}
  ${EndIf}
  !insertmacro CheckAppClosed

  ; Stage the new version next to the old one. Only after every file is in
  ; place does it replace the old version, which stays until then.
  StrCpy $R0 "$INSTDIR.new"
  StrCpy $R1 "$INSTDIR.old"
  SetOutPath "$TEMP"
  Push $R0
  Call ClearOwnedDir
  Push $R1
  Call ClearOwnedDir
  ; Whatever is still at a staging path is not ours: never write into it.
  RMDir "$R0" ; only when empty
  RMDir "$R1"
  ${If} ${FileExists} "$R0\*.*"
  ${OrIf} ${FileExists} "$R1\*.*"
    MessageBox MB_OK|MB_ICONSTOP "$R0 or $R1 already exists and was not created by this installer. Nothing was changed. Move or rename it, then install again." /SD IDOK
    Abort
  ${EndIf}
  StrCpy $R3 0
  SetOutPath "$R0"
  FileOpen $0 "$R0\${MARKER}" w
  FileWrite $0 "${APP_NAME} ${VERSION}$\r$\n"
  FileClose $0
  File /r "${SOURCE_DIR}\*.*"
  ${IfNot} ${FileExists} "$R0\telemetry.exe"
    MessageBox MB_OK|MB_ICONSTOP "The files could not be copied. The installed version was not changed." /SD IDOK
    Abort
  ${EndIf}
  WriteUninstaller "$R0\Uninstall.exe"

  ; Swap. Leave the staging folder first: a folder in use cannot be renamed.
  SetOutPath "$TEMP"
  ${If} ${FileExists} "$INSTDIR\*.*"
    ClearErrors
    Rename "$INSTDIR" "$R1"
    ${If} ${Errors}
      Push $R0
      Call ClearOwnedDir
      MessageBox MB_OK|MB_ICONSTOP "The installed version could not be replaced, probably because a file is in use. Nothing was changed." /SD IDOK
      Abort
    ${EndIf}
    StrCpy $R3 1
  ${EndIf}
  ClearErrors
  Rename "$R0" "$INSTDIR"
  ${If} ${Errors}
    ${If} $R3 == 1
      Rename "$R1" "$INSTDIR"
    ${EndIf}
    Push $R0
    Call ClearOwnedDir
    MessageBox MB_OK|MB_ICONSTOP "The new version could not be put in place. The previous version was restored." /SD IDOK
    Abort
  ${EndIf}
  ; The old version is only deleted if it was ours (the marker travelled with
  ; it, or it is a 0.3.0 install); a leftover is cleaned up by the next run.
  ${If} $R2 == 1
    RMDir /r "$R1"
  ${EndIf}
  SetOutPath "$INSTDIR"

  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\telemetry.exe"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "FlappedEar"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\telemetry.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

; The uninstaller runs in the folder it sits in (or the one `_?=` names), so
; a copy placed in another folder would otherwise delete that folder.
Function un.onInit
  StrCpy $0 "${INSTALL_DIR}"
  StrLen $1 "$LOCALAPPDATA"
  ${If} $1 < 4
  ${OrIf} "$INSTDIR" != "$0"
  ${OrIfNot} ${FileExists} "$INSTDIR\${MARKER}"
    MessageBox MB_OK|MB_ICONSTOP "This uninstaller does not belong to a ${APP_NAME} install in $0. Nothing was deleted." /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}
FunctionEnd

Section "Uninstall"
  !insertmacro CheckAppClosed
  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  ; Verified in un.onInit: the fixed folder, with the install marker. Saved
  ; days are not kept in it.
  SetOutPath "$TEMP"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd

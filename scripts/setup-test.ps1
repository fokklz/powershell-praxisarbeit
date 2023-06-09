if(-not (Test-Path (Join-Path $PWD 'test-data'))) {
    git clone https://github.com/FokklzBulk/powershell-praxisarbeit-test.git test-data
}else{
    Write-Host "Zuruecksetzen: test-data. Dies koennte einen Moment dauern..."
    git -C $PWD/test-data checkout -- . | Out-Null
}


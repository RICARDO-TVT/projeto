param([string]$SQLServerList=$(Throw `
"Paramater missing: -SQLServerList ConfigGroup"))


Function Get-CPUInfo{
    [CmdletBinding()]
    Param(
    [parameter(Mandatory = $TRUE,ValueFromPipeline = $TRUE)]   [String] $ServerName

    )

    Process{
    
            # Get Default SQL Server instance's Edition
            $sqlconn = new-object System.Data.SqlClient.SqlConnection(`
                        "server=$ServerName;Trusted_Connection=true");
            $query = "SELECT SERVERPROPERTY('Edition') AS Edition, SERVERPROPERTY('MachineName') AS MachineName;"

            $sqlconn.Open()
            $sqlcmd = new-object System.Data.SqlClient.SqlCommand ($query, $sqlconn);
            $sqlcmd.CommandTimeout = 0;
            $dr = $sqlcmd.ExecuteReader();

            while ($dr.Read()) { 
             $SQLEdition = $dr.GetValue(0); 
             $MachineName = $dr.GetValue(1);}

            $dr.Close()
            $sqlconn.Close()

   
            #Get processors information            
            $CPU=Get-WmiObject -ComputerName $MachineName -class Win32_Processor
            #Get Computer model information
            $OS_Info=Get-WmiObject -ComputerName $MachineName -class Win32_ComputerSystem
            
     
           #Reset number of cores and use count for the CPUs counting
           $CPUs = 0
           $Cores = 0
           
           foreach($Processor in $CPU){

           $CPUs = $CPUs+1   
           
           #count the total number of cores         
           $Cores = $Cores+$Processor.NumberOfCores
        
          } 
           
           $InfoRecord = New-Object -TypeName PSObject -Property @{
                    Server = $ServerName;
                    Model = $OS_Info.Model;
                    CPUNumber = $CPUs;
                    TotalCores = $Cores;
                    Edition = $SQLEdition;
                    'Cores to CPUs Ratio' = $Cores/$CPUs;
                    Resume = if ($SQLEdition -like "Developer*") {"N/A"} `
                        elseif ($Cores -eq $CPUs) {"No licensing changes"} `
                        else {"licensing costs increase in " + $Cores/$CPUs +" times"};
    }
   Write-Output $InfoRecord
          }
}

#loop through the server list and get information about CPUs, Cores and Default instance edition
Get-Content $SQLServerList | Foreach-Object {Get-CPUInfo $_ }|Format-Table -AutoSize Server, Model, Edition, CPUNumber, TotalCores, 'Cores to CPUs Ratio', Resume
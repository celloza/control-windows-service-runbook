# control-windows-service-runbook
An Azure Runbook that allows stopping and starting of a Windows Service through a Hybrid Runbook Worker.

This runbook allows you to control (stop or start) a Windows Service.

It specifically waits for the service to reach the target state ('Running' if 'action' is 'stop', 'Stopped' if 'action' is 'start') within the provided timespan. If waiting for the state times out, an exception is thrown which can control the flow (as it was originally intended) in a LogicApp.

Exit codes are as follows:

0 - The script executed succesfully.
1 - Invalid parameters specified.
2 - Service was in an invalid state to perform the operation.
3 - A timeout occurred while trying to perform the operation.
4 - No or multiple services found using the provided name.
99 - Unhandled exception.

The output is formatted as JSON for easy consumption in a LogicApp. Sample output is provided below:

```
{
"success": true,
"message": "Service started successfully.",
"errorCode": 0
}
```

To see verbose output, make sure to set the 'Log verbose records' in your Azure Runbook (under Logging and Tracing) to 'On'.

When calling in a Logic App:

![image](https://user-images.githubusercontent.com/3426823/206456556-2244a4c3-7bdb-4d04-8913-f2e702122163.png)

(note the "Wait for Job" which is enabled).

Here's a sample result:

![image](https://user-images.githubusercontent.com/3426823/206457049-7c53c9eb-3587-43a4-a1a6-cb23eee1c243.png)

*! version 0.1 1JAN1900  DIME Analytics dimeanalytics@worldbank.org

cap program drop ietoolkiterror
program define ietoolkiterror

    syntax, [errorid(string)]

    * Prepare the message to be displayed on the screen
    local dimeanaylitics_p_end "Did this error help you figure out what was wrong? If not, please report error ID `errorid' to dimeanalytics@worldbank.org."

    * Display the additional message here
    noi di ""
    noi di as input "{pstd}`dimeanaylitics_p_end'{p_end}"
    noi di ""
end

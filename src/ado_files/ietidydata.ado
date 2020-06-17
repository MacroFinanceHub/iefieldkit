*! version 1.5 28APR2020  DIME Analytics dimeanalytics@worldbank.org

capture program drop ietidydata
		program ietidydata, rclass

	syntax anything, id(varlist) [sep(string)]
	
	reshape long `anything', i(`id') j(newlevel) str
	
end

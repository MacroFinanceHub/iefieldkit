
	use "C:\Users\wb501238\Dropbox\WB\Analytics\DIME Analytics\Data Coordinator\iefieldkit\ietidydata\mockdata.dta", clear
	
	tostring seedsource_* seedtype_*, replace
	
	ietidydata seedsource_ seedtype_ seedtypeone_ seedunit_ seedmzn_ seed_, id(uuid) 
	
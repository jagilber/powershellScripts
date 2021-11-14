<#
test ast class
#>

class TestClass{
    TestClassConstructor (){}

    [void] TestClassFunctionNoParams (){}

    [bool] TestClassFunctionWithParams ([string]$test,[bool]$exists){
        write-host $test
        return $exists
    }
    
}

class TestClass2 {
    [TestClass]$testClass = [TestClass]::new()
    [void] TestClassFunctionNoParams (){}

    [bool] TestClassFunctionWithParams ([string]$test,[bool]$exists){
        write-host $test
        return $exists
    }
}

class TestClass3 {
    [TestClass2]$testClass = [TestClass2]::new()
    [void] TestClassFunctionNoParams3 (){}

    [bool] TestClassFunctionWithParams3 ([string]$test,[bool]$exists){
        write-host $test
        return $exists
    }

    [bool] TestClass2Function(){
        $this.testClass.TestClassFunctionNoParams()
        return $false
    }
}
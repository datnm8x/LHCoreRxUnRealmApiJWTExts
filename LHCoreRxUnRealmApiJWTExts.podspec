Pod::Spec.new do |s|

  s.name             = "LHCoreRxUnRealmApiJWTExts"
  s.version          = "1.0"
  s.summary          = "ListViewModel using with RxRealm, JWT for API, and Unrealm"
  s.swift_version    = "5.0"

  s.description      = <<-DESC
TODO: Add long description of the pod here.
						  DESC

  s.homepage         = 'https://github.com/laohac8x/LHCoreRxUnRealmApiJWTExts'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Dat Ng' => 'laohac83x@gmail.com' }
  s.source           = { :git => 'https://github.com/laohac8x/LHCoreRxUnRealmApiJWTExts.git', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'Pod/Classes/*.swift', 'LHCoreRxApiJWTExts/Source/*.swift', 'LHCoreRxApiJWTExts/LHSwiftJWT/Source/*.swift'

  s.frameworks = 'Foundation'
  s.dependency 'SwiftyJSON', '~> 5'
  s.dependency 'Alamofire', '~> 4'
  s.dependency 'AlamofireImage', '~> 3'
  s.dependency 'RxCocoa', '~> 5'
  s.dependency 'RxSwift', '~> 5'
  s.dependency 'RealmSwift', '3.15.0'
  s.dependency 'Unrealm', '0.1.0'

end

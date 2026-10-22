import copy,importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('release_gate',pathlib.Path(__file__).resolve().parents[2]/'Scripts/release_gate.py')
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
SHA='a'*40

def valid(arch='arm64'):
    return {'schema':1,'application':'RestoreGPSTime','version':'1.0.0','architecture':arch,'minimumOS':'13.0','currentOSMajor':27,'sourceCommit':SHA,'reviewedSourceCommit':SHA,'peerSourceCommit':SHA,'tag':f'v1.0.0-{arch}',
      'signing':{'developerID':True,'hardenedRuntime':True,'notarization':'Accepted','stapled':True,'teamID':'ABCDEFGHIJ'},
      'privacy':{'audited':True,'privateMaterial':False,'secretFound':False},'gates':{g:'pass' for g in gate.REQUIRED_GATES},
      'hosts':[{'architecture':a,'hardwareARM':a=='arm64','translated':False,'osMajor':o,'current':o==27,'status':'pass','sourceCommit':SHA,'appHash':'b'*64} for a in ['arm64','x86_64'] for o in [13,27]],
      'binaries':[{'path':'Contents/MacOS/RestoreGPSTime','architectures':[arch],'minimumOS':'13.0','platform':'macOS','dependencies':['/usr/lib/libSystem.B.dylib']}],
      'assets':[{'name':f'RestoreGPSTime-1.0.0-{"AppleSilicon" if arch=="arm64" else "Intel"}.{ext}','sha256':'c'*64} for ext in ['zip','dmg']]+[{'name':name,'sha256':'c'*64} for name in sorted(gate.COMMON_ASSETS)]}

class ReleaseGateTests(unittest.TestCase):
    def testCompleteSyntheticContract(self):self.assertEqual(gate.validate_manifest(valid()),[])
    def testMissingGateBlocks(self):
        for name in gate.REQUIRED_GATES:
            m=valid();del m['gates'][name];self.assertTrue(gate.validate_manifest(m),name)
    def testMissingInstructionsAndOldCurrentOSBlock(self):
        m=valid();m['assets']=[a for a in m['assets'] if a['name']!='RECOVERY.md'];self.assertTrue(gate.validate_manifest(m))
        m=valid();m['hosts'][1]['osMajor']=14;self.assertTrue(gate.validate_manifest(m))
        m=valid();m['binaries'][0]['platform']='iOS';self.assertTrue(gate.validate_manifest(m))
    def testChangedAssetHashBlocks(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);name='RestoreGPSTime-1.0.0-AppleSilicon.zip';(root/name).write_bytes(b'original')
            m=valid();m['assets']=[{'name':name,'sha256':gate.sha256(root/name)}]
            self.assertEqual(gate.verify_assets(m,root),[])
            (root/name).write_bytes(b'newer content');self.assertTrue(gate.verify_assets(m,root))
    def testRosettaIsNotIntelNative(self):
        m=valid();m['hosts'][2]['hardwareARM']=True;m['hosts'][2]['translated']=True;self.assertTrue(gate.validate_manifest(m))
        m=valid();m['hosts'][2]['translated']=None;self.assertTrue(gate.validate_manifest(m))
    def testWrongArchitectureOrMinOSBlocks(self):
        m=valid();m['binaries'][0]['architectures']=['arm64','x86_64'];self.assertTrue(gate.validate_manifest(m))
        m=valid();m['binaries'][0]['minimumOS']='14.0';self.assertTrue(gate.validate_manifest(m))
        m=valid();m['hosts']=[h for h in m['hosts'] if h['osMajor']!=13];self.assertTrue(gate.validate_manifest(m))
    def testUnsignedIsNotStable(self):
        for field,value in [('developerID',False),('hardenedRuntime',False),('notarization','Invalid'),('stapled',False)]:
            m=valid();m['signing'][field]=value;self.assertTrue(gate.validate_manifest(m))
    def testPrivateFixtureOrSecretBlocks(self):
        for field in ['privateMaterial','secretFound']:
            m=valid();m['privacy'][field]=True;self.assertTrue(gate.validate_manifest(m))
        m=valid();m['assets'].append({'name':'PrivateFixtures.zip','sha256':'a'*64});self.assertTrue(gate.validate_manifest(m))
        m=valid();m['assets'][0]['name']='../leak.zip';self.assertTrue(gate.validate_manifest(m))
    def testTagsMustShareReviewedSource(self):
        a,b=valid(),valid('x86_64');self.assertEqual(gate.validate_pair(a,b),[])
        b['sourceCommit']='d'*40;self.assertTrue(gate.validate_pair(a,b))
        a['reviewedSourceCommit']='e'*40;self.assertTrue(gate.validate_manifest(a))
    def testUploadRetryDoesNotOverwriteDifferentHash(self):
        self.assertEqual(gate.upload_disposition('c'*64,None),'upload')
        self.assertEqual(gate.upload_disposition('c'*64,'c'*64),'skip')
        with self.assertRaises(ValueError):gate.upload_disposition('c'*64,'d'*64)

if __name__=='__main__':unittest.main()

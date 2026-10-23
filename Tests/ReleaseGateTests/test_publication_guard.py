import pathlib,shutil,subprocess,sys,tempfile,unittest,zipfile

SCRIPTS=pathlib.Path(__file__).resolve().parents[2]/'Scripts'
sys.path.insert(0,str(SCRIPTS))
import publication_guard as guard

class PublicationGuardTests(unittest.TestCase):
    def testReportsAndUnreviewedDocsAreRejectedWhileAppSourcesRemainAllowed(self):
        private=['docs/acceptance/EVIDENCE.md','docs/superpowers/plans/update.md',
                 'docs/RELEASE.md','docs/REFERENCE.md','work/run/result.json',
                 'outputs/notes.txt','docs/implementation-notes.md','notes.md',
                 'Scripts/RELEASE-INFO.json','Sources/RestoreGPSTime/Resources/test-report.json',
                 'docs/images/release-evidence.json','Tests/PrivateFixtures/photo.nef',
                 'Scripts/build.log','Tests/results.json','Tests/README.md',
                 'Sources/RestoreGPSTimeCore/Resources/host-matrix.json',
                 'Sources/RestoreGPSTimeCore/Resources/arbitrary-data.json']
        for name in private:self.assertIsNotNone(guard.source_path_error(name),name)
        public=['README.md','docs/INSTALL.md','docs/RECOVERY.md','docs/KNOWN-LIMITS.md',
                'docs/images/preview.jpg','Sources/RestoreGPSTimeCore/Planning/PlanBuilder.swift',
                'Scripts/collect-evidence.sh','Tests/Fixtures/manifest.json','ThirdParty/ExifTool-README.txt',
                'Sources/RestoreGPSTimeCore/Resources/container-capabilities.json',
                'Sources/RestoreGPSTimeCore/Resources/writable-tags.json',
                '.github/workflows/publication.yml','.githooks/pre-push']
        for name in public:self.assertIsNone(guard.source_path_error(name),name)
    def testInternalMaterialCannotBeRenamedToUserHelp(self):
        for text in ['# Implementation plan\nSteps...', '## Test results\n12 passed',
                     'Source: /Users/someone/work/repository', 'Post-signing checks passed: ...',
                     '269 tests passed; one skipped.']:
            self.assertTrue(guard.public_text_errors('INSTALL.md',text),text)
        self.assertEqual(guard.public_text_errors('INSTALL.md','Choose Save copies or change originals.\nUse Full backup for recovery.'),[])
    def testArchiveRejectsReportsAndUnsafePathsButAllowsRuntimeAndLicenses(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            for entry in ['RestoreGPSTime.app/Contents/Resources/RELEASE-INFO.json',
                          'RestoreGPSTime.app/Contents/Resources/reports/test.json',
                          '../INSTALL.md','/private-note.txt','docs/superpowers/design.md','.',
                          'RestoreGPSTime.app/Contents/Resources/build.log',
                          'RestoreGPSTime.app/Contents/Resources/host-matrix.json',
                          'RestoreGPSTime.app/Contents/Resources/results.json']:
                archive=root/'bad.zip'
                with zipfile.ZipFile(archive,'w') as z:z.writestr(entry,'internal report')
                self.assertTrue(guard.zip_errors(archive),entry)
            good=root/'good.zip'
            with zipfile.ZipFile(good,'w') as z:
                z.writestr('RestoreGPSTime.app/Contents/MacOS/RestoreGPSTime',b'program')
                z.writestr('RestoreGPSTime.app/Contents/Resources/build-identity.json','{}')
                z.writestr('ThirdParty/LICENSE.txt','license')
            self.assertEqual(guard.zip_errors(good),[])
            with zipfile.ZipFile(good,'a') as z:z.writestr('INSTALL.md','# Test results\nInternal checks')
            self.assertTrue(guard.zip_errors(good))
    def testForcedStagingCannotBypassIgnores(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo=pathlib.Path(temporary)
            self.git(repo,'init','-q')
            (repo/'.gitignore').write_text('docs/acceptance/\n')
            (repo/'docs/acceptance').mkdir(parents=True)
            (repo/'docs/acceptance/EVIDENCE.md').write_text('internal')
            self.git(repo,'add','-f','docs/acceptance/EVIDENCE.md')
            result=subprocess.run([sys.executable,str(SCRIPTS/'publication_guard.py'),'--repository',str(repo),'--index'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('docs/acceptance/EVIDENCE.md',result.stdout+result.stderr)
    def testNewHistoryCannotHideAReportByDeletingItInALaterCommit(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo=pathlib.Path(temporary)
            self.git(repo,'init','-q');self.git(repo,'config','user.name','Test');self.git(repo,'config','user.email','test@example.invalid')
            (repo/'README.md').write_text('Restore photo dates.');self.git(repo,'add','.');self.git(repo,'commit','-qm','baseline')
            baseline=self.git(repo,'rev-parse','HEAD').strip()
            (repo/'README.md').write_text('Restore photo dates and place names.');self.git(repo,'commit','-qam','user help')
            self.assertEqual(guard.history_errors(repo,'HEAD',baseline),[])
            (repo/'notes.md').write_text('internal plan');self.git(repo,'add','.');self.git(repo,'commit','-qm','notes')
            self.git(repo,'rm','-q','notes.md');self.git(repo,'commit','-qm','remove notes')
            self.assertTrue(guard.history_errors(repo,'HEAD',baseline))
            self.assertTrue(guard.history_errors(repo,'HEAD','f'*40))
    def testInstalledCommitHookRejectsForceAddedInternalFile(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo=pathlib.Path(temporary);self.git(repo,'init','-q')
            self.git(repo,'config','user.name','Test');self.git(repo,'config','user.email','test@example.invalid')
            (repo/'Scripts').mkdir();shutil.copy2(SCRIPTS/'publication_guard.py',repo/'Scripts/publication_guard.py')
            shutil.copy2(SCRIPTS/'install-publication-hooks.sh',repo/'Scripts/install-publication-hooks.sh')
            shutil.copytree(SCRIPTS.parent/'.githooks',repo/'.githooks')
            subprocess.run(['bash',str(repo/'Scripts/install-publication-hooks.sh')],check=True,capture_output=True)
            (repo/'README.md').write_text('Restore dates.');self.git(repo,'add','.')
            self.git(repo,'commit','-qm','public source')
            before=self.git(repo,'rev-parse','HEAD')
            (repo/'docs/acceptance').mkdir(parents=True);(repo/'docs/acceptance/EVIDENCE.md').write_text('private')
            self.git(repo,'add','-f','docs/acceptance/EVIDENCE.md')
            result=subprocess.run(['git','-C',str(repo),'commit','-qm','must be blocked'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Publication blocked',result.stderr)
            self.assertEqual(self.git(repo,'rev-parse','HEAD'),before)
            self.assertTrue((repo/'docs/acceptance/EVIDENCE.md').exists())
    def testPushHookStopsIntermediateReportsBeforeTheyReachARemote(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);repo=root/'checkout';remote=root/'remote.git'
            subprocess.run(['git','clone','--shared','--quiet',str(SCRIPTS.parent),str(repo)],check=True,capture_output=True)
            self.git(repo,'config','user.name','Test');self.git(repo,'config','user.email','test@example.invalid')
            self.git(repo,'config','core.hooksPath','unused-hooks')
            (repo/'notes.md').write_text('internal report');self.git(repo,'add','notes.md');self.git(repo,'commit','-qm','private intermediate commit')
            self.git(repo,'rm','-q','notes.md');self.git(repo,'commit','-qm','remove private file')
            shutil.copy2(SCRIPTS/'publication_guard.py',repo/'Scripts/publication_guard.py')
            (repo/'.githooks').mkdir(exist_ok=True)
            shutil.copy2(SCRIPTS.parent/'.githooks/pre-push',repo/'.githooks/pre-push')
            self.git(repo,'config','core.hooksPath','.githooks')
            subprocess.run(['git','init','--bare','--quiet',str(remote)],check=True,capture_output=True)
            result=subprocess.run(['git','-C',str(repo),'push',str(remote),'HEAD:refs/heads/main'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('notes.md',result.stderr)
            self.assertEqual(self.git(remote,'for-each-ref'), '')
            self.git(repo,'tag','-a','test-publication','-m','test')
            result=subprocess.run(['git','-C',str(repo),'push',str(remote),'refs/tags/test-publication'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('notes.md',result.stderr)
            self.assertEqual(self.git(remote,'for-each-ref'), '')
    def testInstallerPreservesExistingCustomHooks(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo=pathlib.Path(temporary);self.git(repo,'init','-q')
            (repo/'Scripts').mkdir();shutil.copy2(SCRIPTS/'install-publication-hooks.sh',repo/'Scripts/install-publication-hooks.sh')
            (repo/'.git/hooks/pre-commit').write_text('#!/bin/sh\nexit 0\n')
            result=subprocess.run(['bash',str(repo/'Scripts/install-publication-hooks.sh')],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual((repo/'.git/hooks/pre-commit').read_text(),'#!/bin/sh\nexit 0\n')
    def git(self,repo,*args):
        return subprocess.check_output(['git','-C',str(repo),*args],text=True,stderr=subprocess.PIPE)

if __name__=='__main__':unittest.main()

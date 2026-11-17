"""Integration tests: compile bingkit first and set BINGKIT_TEST_BINARY."""
import hashlib,json,os,pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
KIT=os.environ['BINGKIT_TEST_BINARY']
class CollectionTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=pathlib.Path(self.tmp.name);self.root=self.base/'library';self.root.mkdir();self.archive=self.root/'Archived';self.archive.mkdir()
  self.env={**os.environ,'BING_CONFIG':str(self.base/'absent'),'BING_FILENAME_LANGUAGE':'en','BING_FILENAME_CREDIT':'0'}
 def tearDown(self):self.tmp.cleanup()
 def runkit(self,*args,ok=True):
  r=subprocess.run([KIT,*map(str,args)],env=self.env,capture_output=True,text=True)
  if ok:self.assertEqual(r.returncode,0,r.stderr)
  return r
 def image(self,path=None,**fields):
  path=path or self.root/'2026-01-01 Old © Author.jpg'
  f={'dc:title':'标题','dc:description':'气泡星云 NGC 7635','dc:rights':'© Author/Agency','photoshop:DateCreated':'2026-01-01','bing:id':'Nebula','bing:titleEn':'Title','bing:descriptionEn':'Nebula 7635'};f.update(fields)
  self.runkit('tag',ROOT/'tests/pixel.jpg',path,*[k+'='+v for k,v in f.items()]);return path
 def test_four_combinations(self):
  p=self.image()
  for lang in ['en','zh']:
   for c in ['0','1']:
    self.env.update(BING_FILENAME_LANGUAGE=lang,BING_FILENAME_CREDIT=c)
    n=self.runkit('name',p,'2026-01-01').stdout.strip();self.assertIn('Nebula' if lang=='en' else '气泡星云',n);self.assertEqual('©' in n,c=='1')
 def test_archive_and_numeric_names(self):
  p=self.image(self.archive/'2020-01-01 Nebula 7635.jpg');q=self.image(self.root/'2026-01-01 Park turns 75.jpg')
  self.assertEqual(self.runkit('list',self.root).stdout.splitlines(),[str(p),str(q)])
 def test_duplicate_date_skipped(self):
  self.image();self.image(self.archive/'2026-01-01 Other.jpg');r=self.runkit('list',self.root);self.assertEqual(r.stdout,'');self.assertIn('ambiguous',r.stderr)
 def test_preview_apply_restore_bytes(self):
  p=self.image(self.archive/'2020-01-01 Old.jpg');h=hashlib.sha256(p.read_bytes()).hexdigest()
  plan=json.loads(self.runkit('rename',self.root).stdout);self.assertTrue(p.exists());log=self.base/'log.jsonl'
  self.runkit('rename',self.root,'--apply',log);q=pathlib.Path(plan['target']);self.assertFalse(p.exists());self.assertEqual(hashlib.sha256(q.read_bytes()).hexdigest(),h)
  self.runkit('restore',self.root,log);self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),h)
 def test_conflict_exclusive(self):
  p=self.image();q=self.root/'occupied.jpg';q.write_bytes(b'keep');self.assertNotEqual(self.runkit('move',p,q,ok=False).returncode,0);self.assertEqual(q.read_bytes(),b'keep');self.assertTrue(p.exists())
 def test_missing_xmp_skipped(self):
  p=self.root/'2026-01-01 Raw © Author.jpg';shutil.copy(ROOT/'tests/pixel.jpg',p)
  # Strip inherited metadata by using a file deliberately unreadable as JPEG.
  p.write_bytes(b'not a jpeg');self.assertNotEqual(self.runkit('rename',self.root,ok=False).returncode,0);self.assertTrue(p.exists())
 def test_fallback_and_sanitization(self):
  p=self.image(**{'bing:descriptionEn':'\n / : *** \n'+'😀'*200})
  n=self.runkit('name',p,'2026-01-01').stdout.strip();self.assertLessEqual(len(n.encode()),251);self.assertNotIn('/',n);self.assertNotIn('\n',n)
 def test_fill_preserves_existing_title(self):
  p=self.image(**{'bing:descriptionEn':''});q=self.base/'filled.jpg'
  self.assertIn('\t0\t',self.runkit('info',p).stdout)
  self.runkit('fill',p,q,'bing:titleEn=Wrong','bing:descriptionEn=Recovered')
  f=json.loads(self.runkit('fields',q).stdout)['fields'];self.assertEqual(f['bing:titleEn'],'Title');self.assertEqual(f['bing:descriptionEn'],'Recovered')
 def mocks(self,caption_fail=False):
  bins=self.base/'bin';bins.mkdir()
  for name,body in {'swift':f'#!/bin/bash\n'+('if [ "$2" = caption ]; then exit 1; fi\n' if caption_fail else '')+f'exec "{KIT}" "${{@:2}}"\n','xcrun':'#!/bin/bash\necho /usr/bin/swift\n'}.items():
   f=bins/name;f.write_text(body);f.chmod(0o755)
  self.env['PATH']=str(bins)+':'+os.environ['PATH'];self.env['BING_ROTATION_DIR']=str(self.base/'rotation')
  return bins
 def test_failed_rotation_keeps_old(self):
  self.image(self.archive/'2020-01-01 New.jpg');self.mocks(True);out=self.base/'rotation';out.mkdir();old=out/'old.jpg';old.write_bytes(b'keep')
  r=subprocess.run(['bash',str(ROOT/'rotation.sh'),str(self.root)],env=self.env,capture_output=True,text=True);self.assertNotEqual(r.returncode,0);self.assertEqual(old.read_bytes(),b'keep');self.assertFalse((self.root/'.bing-operation.lock').exists())
 def test_invalid_config_no_writes(self):
  self.env['BING_FILENAME_LANGUAGE']='';r=subprocess.run(['bash',str(ROOT/'bing.sh'),str(self.root)],env=self.env,capture_output=True,text=True);self.assertEqual(r.returncode,2);self.assertEqual(list(self.root.iterdir()),[self.archive])
 def test_restore_rejects_changed_target(self):
  self.image();log=self.base/'log';r=self.runkit('rename',self.root,'--apply',log);q=pathlib.Path(json.loads(r.stdout)['target']);q.write_bytes(b'changed')
  self.assertNotEqual(self.runkit('restore',self.root,log,ok=False).returncode,0);self.assertEqual(q.read_bytes(),b'changed')
 def test_valid_missing_xmp(self):
  p=self.root/'2026-01-01 Raw © Author.jpg';shutil.copy(ROOT/'tests/pixel.jpg',p)
  self.assertNotEqual(self.runkit('rename',self.root,ok=False).returncode,0);self.assertTrue(p.exists())
 def test_unicode_joiner_tag(self):
  p=self.image(**{'dc:title':'\u200cTitle'});self.assertEqual(json.loads(self.runkit('fields',p).stdout)['fields']['dc:title'],'\u200cTitle')
 def downloader(self,fail=False,archived=False):
  bins=self.mocks()
  if fail:
   f=bins/'swift';f.write_text(f'#!/bin/bash\nif [ "$2" = tag ]; then exit 1; fi\nexec "{KIT}" "${{@:2}}"\n');f.chmod(0o755)
  curl=bins/'curl'
  curl.write_text('#!/usr/bin/env python3\nimport sys,json,shutil\na=sys.argv;out=a[a.index("-o")+1];url=a[-1]\nif "_UHD.jpg" in url: shutil.copy('+repr(str(ROOT/'tests/pixel.jpg'))+',out)\nelse:\n en="ensearch=1" in url\n r={"startdate":"20260101","fullstartdate":"202601010000","urlbase":"/th?id=OHR.Test_ZH-CN123","title":"Title" if en else "标题","copyright":"English scene (© Author)" if en else "中文场景 (© Author)","copyrightlink":"https://www.bing.com/search?q=test"}\n open(out,"w").write(json.dumps({"images":[r]}))\n');curl.chmod(0o755)
  if archived:self.image(self.archive/'2026-01-01 Existing.jpg')
  r=subprocess.run(['bash',str(ROOT/'bing.sh'),str(self.root)],env=self.env,capture_output=True,text=True)
  return r
 def test_download_xmp_failure_retry(self):
  r=self.downloader(True);self.assertNotEqual(r.returncode,0,r.stderr);self.assertEqual(list(self.root.glob('*.jpg')),[])
  ledger=self.root/'.bing-downloaded';self.assertFalse(ledger.exists() and '2026-01-01' in ledger.read_text())
 def test_download_english_default(self):
  r=self.downloader();self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.root/'2026-01-01 English scene.jpg').exists())
 def test_download_deduplicates_archive(self):
  r=self.downloader(archived=True);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(list(self.root.glob('*.jpg')),[])
 def test_busy_lock_not_removed(self):
  lock=self.root/'.bing-operation.lock';lock.mkdir();(lock/'pid').write_text('other')
  r=subprocess.run(['bash',str(ROOT/'bing.sh'),str(self.root)],env=self.env,capture_output=True,text=True)
  self.assertNotEqual(r.returncode,0);self.assertEqual((lock/'pid').read_text(),'other')
 def test_rotation_output_cannot_overlap_collection(self):
  for out in [self.root,self.archive,self.base]:
   self.assertNotEqual(self.runkit('check-output',self.root,out,ok=False).returncode,0)
  self.runkit('check-output',self.root,self.base/'rotation')
 def test_control_character_source_can_migrate(self):
  p=self.image(self.archive/'2020-01-01 \u200cOld\nName.jpg')
  r=self.runkit('rename',self.root);self.assertEqual(json.loads(r.stdout)['source'],str(p))
  log=self.base/'control-log';self.runkit('rename',self.root,'--apply',log);self.assertFalse(p.exists())
  self.runkit('restore',self.root,log);self.assertTrue(p.exists())
if __name__=='__main__':unittest.main()

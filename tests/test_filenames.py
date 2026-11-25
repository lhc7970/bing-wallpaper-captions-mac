"""Integration tests: compile bingkit first and set BINGKIT_TEST_BINARY."""
import datetime
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
 def mocks(self,fail_command=None):
  bins=self.base/'bin'
  bins.mkdir()
  self.env['BING_TEST_MOVE_SOURCE']=str(self.base/'move-source')
  self.env['BING_TEST_FILL_PATH']=str(self.base/'fill-path')
  wrapper='#!/bin/bash\nif [ "$2" = move ]; then printf "%s" "$3" > "$BING_TEST_MOVE_SOURCE"; fi\n'
  wrapper+='if [ "$2" = fill ]; then printf "%s" "$4" > "$BING_TEST_FILL_PATH"; fi\n'
  if fail_command:
   wrapper+=f'if [ "$2" = {fail_command} ]; then exit 1; fi\n'
  wrapper+=f'exec "{KIT}" "${{@:2}}"\n'
  for name,body in {'swift':wrapper,'xcrun':'#!/bin/bash\necho /usr/bin/swift\n'}.items():
   f=bins/name;f.write_text(body);f.chmod(0o755)
  self.env['PATH']=str(bins)+':'+os.environ['PATH'];self.env['BING_ROTATION_DIR']=str(self.base/'rotation')
  return bins
 def test_failed_rotation_keeps_old(self):
  self.image(self.archive/'2020-01-01 New.jpg');self.mocks("caption");out=self.base/'rotation';out.mkdir();old=out/'old.jpg';old.write_bytes(b'keep')
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
 def prepare_downloader(self,fail_command=None):
  bins=self.mocks(fail_command)
  self.day=datetime.date.today().isoformat()
  self.env['BING_TEST_DAY']=self.day.replace('-','')
  self.env['BING_TEST_PIXEL']=str(ROOT/'tests/pixel.jpg')
  temp=self.base/'Wallpaper SSD [tmp]'
  temp.mkdir()
  self.env['TMPDIR']=str(temp)
  curl=bins/'curl'
  curl.write_text("""#!/usr/bin/env python3
import json, os, shutil, sys
out = sys.argv[sys.argv.index('-o') + 1]
url = sys.argv[-1]
if '_UHD.jpg' in url:
    shutil.copy(os.environ['BING_TEST_PIXEL'], out)
else:
    en = 'ensearch=1' in url
    day = os.environ['BING_TEST_DAY']
    row = {'startdate': day, 'fullstartdate': day + '0000', 'urlbase': '/th?id=OHR.Test_ZH-CN123',
           'title': 'Title' if en else '标题', 'copyright': 'English scene (© Author)' if en else '中文场景 (© Author)',
           'copyrightlink': 'https://www.bing.com/search?q=test'}
    with open(out, 'w') as f:
        json.dump({'images': [row]}, f)
""")
  curl.chmod(0o755)
 def downloader(self,fail_command=None,archived=False):
  self.prepare_downloader(fail_command)
  if archived:self.image(self.archive/f'{self.day} Existing.jpg')
  return self.run_download()
 def run_download(self):
  return subprocess.run(['bash',str(ROOT/'bing.sh'),str(self.root)],env=self.env,capture_output=True,text=True)
 def assert_download_failed(self,command):
  r=self.downloader(command)
  self.assertEqual(r.returncode,1,r.stderr)
  self.assertEqual(list(self.root.iterdir()),[self.archive])
  self.assertEqual(list(pathlib.Path(self.env['TMPDIR']).iterdir()),[])
 def test_download_xmp_failure_retry(self):
  self.assert_download_failed('tag')
 def test_download_publication_failure(self):
  self.assert_download_failed('move')
 def assert_downloaded(self):
  r=self.downloader()
  self.assertEqual(r.returncode,0,r.stderr)
  source=pathlib.Path((self.base/'move-source').read_text())
  self.assertIn(self.root,source.parents)
  image=self.root/f'{self.day} English scene.jpg'
  self.assertEqual(json.loads(self.runkit('fields',image).stdout)['fields']['bing:id'],'Test')
  self.assertEqual((self.root/'.bing-downloaded').read_text().splitlines(),[self.day])
  self.assertFalse(list(self.root.glob('.bing-stage.*')))
 def test_download_english_default(self):
  self.assert_downloaded()
 def assert_archived_backfill(self):
  day=datetime.date.today()-datetime.timedelta(days=1)
  self.env['BING_TEST_DAY']=day.strftime('%Y%m%d')
  original=self.image(self.archive/f'{day} Existing.jpg',**{'bing:id':'Test','bing:descriptionEn':''})
  before=json.loads(self.runkit('fields',original).stdout)['fields']
  r=self.run_download()
  self.assertEqual(r.returncode,0,r.stderr)
  after=json.loads(self.runkit('fields',original).stdout)['fields']
  self.assertEqual(after,{**before,'bing:descriptionEn':'English scene'})
  staged=pathlib.Path((self.base/'fill-path').read_text())
  self.assertIn(original.parent,staged.parents)
  self.assertEqual(list(self.archive.iterdir()),[original])
 def test_archived_backfill(self):
  self.prepare_downloader()
  self.assert_archived_backfill()
 def test_failed_archived_backfill_preserves_original(self):
  self.prepare_downloader('fill')
  original=self.image(self.archive/f'{self.day} Existing.jpg',**{'bing:id':'Test','bing:descriptionEn':''})
  before=original.read_bytes()
  r=self.run_download()
  self.assertIn('could not add English text',r.stderr)
  self.assertEqual(original.read_bytes(),before)
  self.assertEqual(list(self.archive.iterdir()),[original])
 @unittest.skipUnless(os.environ.get('BING_TEST_VOLUME'),'set BING_TEST_VOLUME to a writable directory on a second volume')
 def test_download_across_volumes(self):
  with tempfile.TemporaryDirectory(dir=os.environ['BING_TEST_VOLUME']) as folder:
   self.root=pathlib.Path(folder)/'Wallpaper Collection'
   self.assertNotEqual(self.base.stat().st_dev,self.root.parent.stat().st_dev,'BING_TEST_VOLUME must be on a different filesystem from TMPDIR')
   self.assert_downloaded()
   self.archive=self.root/'Archived'
   self.archive.mkdir()
   self.assert_archived_backfill()
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
 def rotation(self,collection):
  return subprocess.run(['bash',str(ROOT/'rotation.sh'),str(collection)],env=self.env,capture_output=True,text=True)
 def test_rotation_with_trailing_slashes(self):
  original=self.image()
  archived=self.image(self.archive/'2020-01-01 Older.jpg')
  self.mocks()
  r=self.rotation(str(self.root)+'///')
  self.assertEqual(r.returncode,0,r.stderr)
  self.assertEqual({p.name for p in (self.base/'rotation').glob('*.jpg')},{original.name,archived.name})
 def test_rotation_rejects_case_aliases(self):
  alias=self.base/self.root.name.upper()
  if not alias.exists():
   self.runkit('check-output',self.root,alias/'new')
   self.skipTest('case-sensitive filesystem')
  self.assertTrue(alias.samefile(self.root))
  self.mocks()
  for collection,out in [(self.root,alias/'new'/'rotation'),(self.archive,alias),(self.root,alias)]:
   self.env['BING_ROTATION_DIR']=str(out)
   r=self.rotation(collection)
   self.assertEqual(r.returncode,1,r.stderr)
   self.assertIn('must not overlap',r.stderr)
  self.assertEqual(list(self.root.iterdir()),[self.archive])
 def test_rotation_output_through_symlink(self):
  alias=self.base/'linked archive'
  alias.symlink_to(self.archive)
  out=alias/'..'/'new'
  self.assertIn('must not overlap',self.runkit('check-output',self.root,out,ok=False).stderr)
  self.assertFalse(out.exists())
 def test_rotation_rejects_combining_mark_after_symlink(self):
  self.image()
  alias=self.base/'alias'
  alias.symlink_to(self.root)
  self.mocks()
  out=alias/'\u0301new'
  self.env['BING_ROTATION_DIR']=str(out)
  r=self.rotation(self.root)
  self.assertFalse(out.exists())
  self.assertEqual(r.returncode,1,r.stderr)
  self.assertIn('must not overlap',r.stderr)
 def test_rotation_collection_with_trailing_newline(self):
  physical=self.base/'photos\n'
  sibling=self.base/'photos'
  physical.mkdir()
  sibling.mkdir()
  alias=self.base/'collection'
  alias.symlink_to(physical)
  wanted=self.image(physical/'2026-01-01 Wanted.jpg')
  self.image(sibling/'2026-01-01 Wrong.jpg')
  self.mocks()
  out=pathlib.Path(self.env['BING_ROTATION_DIR'])
  for collection in (alias,physical):
   with self.subTest(collection=collection):
    r=self.rotation(collection)
    self.assertEqual(r.returncode,0,r.stderr)
    self.assertEqual(list(out.glob('*.jpg')),[out/wanted.name])
 def test_control_character_source_can_migrate(self):
  p=self.image(self.archive/'2020-01-01 \u200cOld\nName.jpg')
  r=self.runkit('rename',self.root);self.assertEqual(json.loads(r.stdout)['source'],str(p))
  log=self.base/'control-log';self.runkit('rename',self.root,'--apply',log);self.assertFalse(p.exists())
  self.runkit('restore',self.root,log);self.assertTrue(p.exists())
if __name__=='__main__':unittest.main()

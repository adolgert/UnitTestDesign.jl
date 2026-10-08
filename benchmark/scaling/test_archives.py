"""Check that evidence survives source edits and raw-directory cleanup."""
import hashlib, importlib.util, json, pathlib, tempfile, unittest, zipfile

module_spec=importlib.util.spec_from_file_location('scaling_summary',pathlib.Path(__file__).with_name('summarize.py'))
summary=importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(summary)


class ArchiveTests(unittest.TestCase):
    def test_preserves_raw_and_distinct_external_sources_after_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            sources={}
            expected={}
            for name in ('first','second'):
                parent=root/name
                parent.mkdir()
                source=parent/'adapter.jl'
                data=f'# {name}\n'.encode()
                source.write_bytes(data)
                sources[str(source)]=hashlib.sha256(data).hexdigest()
                expected[str(source)]=data
            study=root/'study'
            job=study/'job'
            job.mkdir(parents=True)
            (study/'results.json').write_text(json.dumps({'metadata':{'source_sha256':sources}}))
            raw=b'{"event":"done"}\n'
            (job/'events.jsonl').write_bytes(raw)
            summary.archive(study)
            # Re-archive after the working sources changed and ignored raw
            # directories disappeared. The original evidence must survive.
            (job/'events.jsonl').unlink()
            job.rmdir()
            for source in sources: pathlib.Path(source).write_text('# changed\n')
            summary.archive(study)
            with zipfile.ZipFile(study/'raw_jobs.zip') as archive:
                self.assertEqual(archive.read('job/events.jsonl'),raw)
            with zipfile.ZipFile(study/'protocol_snapshot.zip') as archive:
                entries=[name for name in archive.namelist() if name.endswith('/adapter.jl')]
                self.assertEqual(len(entries),2)
                self.assertEqual({archive.read(name) for name in entries},set(expected.values()))

    def test_refuses_unavailable_measured_source(self):
        with tempfile.TemporaryDirectory() as directory:
            study=pathlib.Path(directory)
            source=study/'adapter.jl'
            digest=hashlib.sha256(b'# measured\n').hexdigest()
            source.write_text('# changed\n')
            (study/'results.json').write_text(json.dumps({'metadata':{'source_sha256':{str(source):digest}}}))
            with self.assertRaisesRegex(RuntimeError,'Cannot archive measured source'):
                summary.archive(study)
            self.assertFalse((study/'protocol_snapshot.zip').exists())


if __name__=='__main__': unittest.main()

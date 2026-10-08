from pathlib import Path
import hashlib
import unittest
from PIL import Image
from empire_front.cards import CARDS


class CardArtTests(unittest.TestCase):
    def test_every_card_has_its_own_valid_illustration(self):
        folder=Path(__file__).resolve().parents[1]/"assets"/"cards"
        hashes=[]
        for key in CARDS:
            file=folder/f"{key}.png"
            self.assertTrue(file.is_file(),f"缺少{CARDS[key]['name']}的插画")
            with Image.open(file) as picture:
                self.assertEqual(picture.format,"PNG")
                self.assertGreaterEqual(min(picture.size),640)
                picture.verify()
            hashes.append(hashlib.sha256(file.read_bytes()).hexdigest())
        self.assertEqual(len(set(hashes)),len(CARDS),"不同卡牌不能复用同一个插画文件")

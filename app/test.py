from app import app
import unittest


class Test(unittest.TestCase):

    def setUp(self):
        self.app = app.test_client()

    def test_requisicao(self):
        result = self.app.get("/")
        self.assertEqual(result.status_code, 200)

    def test_conteudo(self):
        result = self.app.get("/")
        self.assertRegex(result.data.decode(), "Escreva uma Mensagem para o Cabecalho da Pagina.")

    def test_health(self):
        result = self.app.get("/health")
        self.assertEqual(result.status_code, 200)
        data = result.get_json()
        self.assertEqual(data["status"], "ok")


if __name__ == "__main__":
    print("INICIANDO OS TESTES")
    print("----------------------------------------------------------------------")
    unittest.main(verbosity=2)

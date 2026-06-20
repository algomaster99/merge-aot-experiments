package dev.fopexp;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;
import org.w3c.dom.Text;
import org.xml.sax.Attributes;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;
import org.xml.sax.helpers.DefaultHandler;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.SAXParser;
import javax.xml.parsers.SAXParserFactory;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import java.io.StringReader;
import java.io.StringWriter;

public class XmlApisWorkload {

    public static void main(String[] args) throws Exception {
        exerciseDom();
        exerciseSax();
        exerciseTransformer();
    }

    private static void exerciseDom() throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        DocumentBuilder builder = factory.newDocumentBuilder();

        Document doc = builder.newDocument();
        Element root = doc.createElementNS("http://www.w3.org/2000/svg", "svg");
        root.setAttribute("width", "100");
        root.setAttribute("height", "100");
        doc.appendChild(root);

        Element rect = doc.createElement("rect");
        rect.setAttribute("x", "10");
        rect.setAttribute("y", "10");
        rect.setAttribute("width", "80");
        rect.setAttribute("height", "80");
        root.appendChild(rect);

        Element text = doc.createElement("text");
        Text textNode = doc.createTextNode("hello xml-apis");
        text.appendChild(textNode);
        root.appendChild(text);

        NodeList children = root.getChildNodes();
        for (int i = 0; i < children.getLength(); i++) {
            org.w3c.dom.Node child = children.item(i);
            if (child instanceof Element) {
                Element el = (Element) child;
                el.getAttributeNode("x");
            }
        }

        String xml = "<root><child attr=\"val\">content</child></root>";
        Document parsed = builder.parse(new InputSource(new StringReader(xml)));
        parsed.getDocumentElement().getTagName();
    }

    private static void exerciseSax() throws Exception {
        SAXParserFactory factory = SAXParserFactory.newInstance();
        factory.setNamespaceAware(true);
        SAXParser parser = factory.newSAXParser();

        String xml = "<items><item id=\"1\">alpha</item><item id=\"2\">beta</item></items>";
        parser.parse(new InputSource(new StringReader(xml)), new DefaultHandler() {
            @Override
            public void startElement(String uri, String localName, String qName, Attributes attrs) throws SAXException {
                for (int i = 0; i < attrs.getLength(); i++) {
                    attrs.getQName(i);
                    attrs.getValue(i);
                }
            }
        });
    }

    private static void exerciseTransformer() throws Exception {
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        Document doc = dbf.newDocumentBuilder().newDocument();
        Element root = doc.createElement("data");
        root.setTextContent("xml-apis transformer path");
        doc.appendChild(root);

        TransformerFactory tf = TransformerFactory.newInstance();
        Transformer transformer = tf.newTransformer();
        StringWriter sw = new StringWriter();
        transformer.transform(new DOMSource(doc), new StreamResult(sw));
        sw.toString();
    }
}

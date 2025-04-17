# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

{
    'name': 'Custom account',
    'version': '12.0.0.0.0',
    'category': 'Accounting',
    'summary': 'Custom sale to print Quotation and Invoice',
    'sequence': '8',
    'author': 'Loomoni Morwo',
    'website': 'http://loomoni.com',
    'depends': ['account'],
    'demo': [],

    'data': [
        'views/account_invoice_views.xml',
    ],

    'installable': True,
    'application': True,
    'auto_install': False,
    'qweb': [],
}
